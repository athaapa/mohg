#!/usr/bin/env python3
"""Record a scaling sweep and fit sampled cycle costs; stdlib only."""
import argparse
import csv
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent


def run(*args):
    print('+', ' '.join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), cwd=ROOT, check=True)


class Table:
    def __init__(self, path):
        self.root = ET.parse(path).getroot()
        self.ids = {e.get('id'): e for e in self.root.iter() if e.get('id')}
        self.rows = []
        for node in self.root.findall('node'):
            columns = [c.findtext('mnemonic') for c in node.find('schema')]
            self.rows.extend(dict(zip(columns, row)) for row in node.findall('row'))

    def resolve(self, element):
        while element is not None and element.get('ref'):
            element = self.ids[element.get('ref')]
        return element

    def text(self, element):
        element = self.resolve(element)
        return '' if element is None else (element.text or '')

    def identity(self, element, field):
        element = self.resolve(element)
        return self.text(element.find(field)) if element is not None else ''


def intervals(path):
    table = Table(path)
    active, result = {}, []
    for row in table.rows:
        if table.text(row['subsystem']) != 'mohg.bench' or table.text(row['name']) != 'Render blocks':
            continue
        pid = table.identity(row['process'], 'pid')
        key = pid, table.text(row['identifier'])
        event = table.text(row['event-type'])
        if event == 'Begin':
            message = table.resolve(row['message'])
            # Rebuild metadata from typed children, not locale-formatted fmt attributes.
            text = ''.join(table.text(e) for e in message)
            fields = dict(re.findall(r'(phase|n|k|L|F|B)=\s*([^\s]+)', text))
            required = {'phase', 'n', 'k', 'L', 'F', 'B'}
            if fields.keys() != required:
                raise ValueError(f'Unexpected signpost metadata: {text}')
            record = {k: int(v) if k != 'phase' else v for k, v in fields.items()}
            record.update(start=int(table.text(row['time'])), pid=pid,
                          tid=table.identity(row['thread'], 'tid'))
            active[key] = record
        elif event == 'End' and key in active:
            record = active.pop(key)
            record.update(end=int(table.text(row['time'])), cycles=0, samples=0, cores={})
            result.append(record)
    if active:
        raise ValueError('Trace has unfinished benchmark intervals; recording may be truncated')
    if not result:
        raise ValueError('No mohg.bench / Render blocks intervals found; enable Points of Interest')
    return sorted(result, key=lambda r: r['start'])


def aggregate(records, path, cycle_index):
    table = Table(path)
    by_thread = {}
    for record in records:
        by_thread.setdefault((record['pid'], record['tid']), []).append(record)
    for row in table.rows:
        key = (table.identity(row['process'], 'pid'), table.identity(row['thread'], 'tid'))
        if key not in by_thread or table.text(row['thread-state']) != 'Running':
            continue
        counters = table.text(row['counters-array']).split()
        if not counters:
            continue
        if cycle_index >= len(counters):
            raise ValueError('Cycle index does not match exported counter array')
        timestamp = int(table.text(row['time']))
        for record in by_thread[key]:
            if record['start'] <= timestamp < record['end']:
                record['cycles'] += int(counters[cycle_index])
                record['samples'] += 1
                core = table.text(row['core'])
                record['cores'][core] = record['cores'].get(core, 0) + 1
                break


def line_fit(points):
    if len(points) < 2:
        raise ValueError('Need at least two points per sweep')
    mx = sum(x for x, y in points) / len(points)
    my = sum(y for x, y in points) / len(points)
    denominator = sum((x - mx) ** 2 for x, y in points)
    if not denominator:
        raise ValueError('Sweep has no variation')
    slope = sum((x - mx) * (y - my) for x, y in points) / denominator
    intercept = my - slope * mx
    residuals = [y - (slope * x + intercept) for x, y in points]
    return slope, intercept, residuals


def fit_costs(records):
    groups = {phase: [r for r in records if r['phase'] == phase]
              for phase in ('unison', 'voices', 'baseline')}
    u, v, z = (groups[k] for k in ('unison', 'voices', 'baseline'))
    if not all(groups.values()) or any(r['samples'] == 0 for r in u + v + z):
        raise ValueError('Need sampled unison, voice, and baseline sweeps for a/b/c/d')
    if len({(r['n'], r['L']) for r in u}) != 1 or len({(r['k'], r['L']) for r in v}) != 1:
        raise ValueError('Expected fixed n/L in unison sweep and fixed k/L in voice sweep')
    if any(r['n'] != 0 for r in z):
        raise ValueError('Baseline must have zero voices')
    # Normalize by F*B first so longer baseline recordings remain comparable.
    per_frame = lambda r: r['cycles'] / (r['F'] * r['B'])
    a, _, ur = line_fit([(r['k'], per_frame(r) / (r['L'] * r['n'])) for r in u])
    voice_slope, _, vr = line_fit([(r['n'], per_frame(r) / r['L']) for r in v])
    c, d, zr = line_fit([(r['L'], per_frame(r)) for r in z])
    b = voice_slope - v[0]['k'] * a
    costs = dict(a=a, b=b, c=c, d=d)
    errors = []
    for r in records:
        predicted = r['F'] * r['B'] * (r['L'] * (r['n'] * (r['k'] * a + b) + c) + d)
        errors.append(100 * (r['cycles'] - predicted) / r['cycles'] if r['cycles'] else None)
    return dict(costs=costs, residual_percent=errors,
                sweep_residuals=dict(unison=ur, voices=vr, baseline=zr))


def analyze(toc, signposts, counters):
    root = ET.parse(toc).getroot()
    tables = root.findall('.//table[@schema="counters-profile"]')
    if len(tables) != 1:
        raise ValueError('Expected one counters-profile table in a single-run trace')
    events = re.findall(r'"([^"]+)"|(\S+)', tables[0].get('pmc-events', ''))
    events = [a or b for a, b in events]
    if 'Cycles' not in events:
        raise ValueError(f'Template did not record Cycles: {events}')
    records = intervals(signposts)
    aggregate(records, counters, events.index('Cycles'))
    print('\nSampled cycle estimates (whole measured loop, including timer overhead)')
    print(f'{"phase":9} {"n":>3} {"k":>3} {"L":>3} {"F":>4} {"B":>7} {"samples":>8} {"cycles":>16}')
    for r in records:
        print(f'{r["phase"]:9} {r["n"]:3} {r["k"]:3} {r["L"]:3} {r["F"]:4} {r["B"]:7} {r["samples"]:8} {r["cycles"]:16,}')
        if r['samples'] < 100:
            print('  WARNING: fewer than 100 counter samples; increase blocks (especially baseline-blocks).')
    result = {'intervals': records, 'counter_events': events}
    try:
        result['fit'] = fit_costs(records)
    except ValueError as error:
        print(f'\nFit unavailable: {error}')
        return result
    print('\nEstimated cycles per model operation (not exact hardware snapshots):')
    labels = dict(a='oscillator iteration', b='voice-subframe', c='subframe', d='output frame')
    for name, value in result['fit']['costs'].items():
        print(f'  {name} = {value:12.3f}  {labels[name]}')
    print('\nModel residuals: (observed - predicted) / observed')
    for r, error in zip(records, result['fit']['residual_percent']):
        print(f'  {r["phase"]:9} n={r["n"]:2} k={r["k"]:2} L={r["L"]:2}: {error:+.2f}%')
    if any(abs(e) > 10 for e in result['fit']['residual_percent']):
        print('WARNING: model residual exceeds 10%; repeat/lengthen runs and check the model before trusting coefficients.')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--trace', type=Path, help='Analyze an existing single-run trace instead of recording')
    parser.add_argument('--template', default='perf1', help='Saved CPU Counters + signposts template')
    parser.add_argument('--output', type=Path, help='New output directory (default: unique directory under build/profiles)')
    parser.add_argument('--no-build', action='store_true', help='Use the existing build/bench executable')
    parser.add_argument('bench_args', nargs=argparse.REMAINDER, help='Scaling arguments after --')
    args = parser.parse_args()
    if args.output:
        output = args.output.resolve()
        output.mkdir(parents=True, exist_ok=False)
    else:
        parent = ROOT / 'build' / 'profiles'
        parent.mkdir(parents=True, exist_ok=True)
        output = Path(tempfile.mkdtemp(prefix='cycles-', dir=parent))
    print(f'Artifacts: {output}', flush=True)
    trace = args.trace.resolve() if args.trace else output / 'scaling.trace'
    if not args.trace:
        if not args.no_build:
            (ROOT / 'build').mkdir(exist_ok=True)
            run('clang', '-fblocks', '-O2', '-g', '-c', 'src/core_midi_bridge.c', '-o', 'build/core_midi_bridge.o')
            run('clang', '-O2', '-g', '-c', 'bench/signpost_bridge.c', '-o', 'build/signpost_bridge.o')
            run('odin', 'build', 'bench', '-o:speed', '-debug', '-out:build/bench')
        extra = args.bench_args
        if extra[:1] == ['--']:
            extra = extra[1:]
        run('xcrun', 'xctrace', 'record', '--template', args.template, '--output', trace,
            '--launch', '--', ROOT / 'build' / 'bench', 'scaling', *extra)
    toc, signposts, counters = (output / name for name in ('toc.xml', 'signposts.xml', 'counters.xml'))
    run('xcrun', 'xctrace', 'export', '--input', trace, '--toc', '--output', toc)
    for schema, path in [('os-signpost', signposts), ('counters-profile', counters)]:
        run('xcrun', 'xctrace', 'export', '--input', trace, '--xpath',
            f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]', '--output', path)
    result = analyze(toc, signposts, counters)
    (output / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
    records = result['intervals']
    with (output / 'intervals.csv').open('w', newline='') as file:
        fields = ['phase', 'n', 'k', 'L', 'F', 'B', 'start', 'end', 'samples', 'cycles']
        writer = csv.DictWriter(file, fieldnames=fields, extrasaction='ignore')
        writer.writeheader()
        writer.writerows(records)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, ET.ParseError, subprocess.CalledProcessError) as error:
        print(f'error: {error}', file=sys.stderr)
        sys.exit(1)
