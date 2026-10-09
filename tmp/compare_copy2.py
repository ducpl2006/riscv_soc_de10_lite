from collections import Counter
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess

root = Path(__file__).resolve().parents[1]
archive = Path(r'C:\FPGA\riscv_soc_de10_lite - Copy2.rar')
review = root / 'tmp/review_copy2_20260930'
review.mkdir(exist_ok=True)
listing = (root / 'tmp/copy2_archive_listing.txt').read_text(encoding='utf-16')
records = []
for block in listing.split('----------\n', 1)[1].split('\n\n'):
    entry = dict(line.split(' = ', 1) for line in block.splitlines() if ' = ' in line)
    if entry.get('Folder') == '-':
        records.append(entry)
prefixes = {entry['Path'].replace('\\', '/').split('/')[0] for entry in records}
assert len(prefixes) == 1, prefixes
prefix = next(iter(prefixes))

def selected(name):
    parts = PurePosixPath(name).parts
    excluded = {'.git', '.tools', '.venv', 'venv', '__pycache__', '.pytest_cache',
                'node_modules', 'db', 'incremental_db', 'output_files', 'tmp', 'sim'}
    if any(p in excluded for p in parts) or parts[-1] == 'transcript':
        return False
    if parts[0] == 'firmware' and 'build' in parts:
        return name in ('firmware/build/boot.hex', 'firmware/build/boot.mif')
    if parts[0] == 'ml' and 'artifacts' in parts:
        return False
    return True

keep = []
for entry in records:
    normalized = entry['Path'].replace('\\', '/')
    parts = PurePosixPath(normalized).parts
    assert not PurePosixPath(normalized).is_absolute()
    assert '..' not in parts and not any(':' in part for part in parts), normalized
    assert not any(entry.get(key) for key in ('Symbolic Link', 'Hard Link', 'Copy Link')), normalized
    assert entry.get('Alternate Stream') != '+', normalized
    relative = '/'.join(parts[1:])
    if selected(relative):
        keep.append((entry['Path'], relative, int(entry['Size'])))
print('Nguồn trong RAR:', prefix)
print('Tổng số tệp:', len(records))
print('Chọn đối chiếu:', len(keep), 'tệp;', sum(size for _, _, size in keep), 'byte')
print('Theo thư mục:', dict(Counter(PurePosixPath(rel).parts[0] for _, rel, _ in keep)))
file_list = review / 'extract_list.txt'
file_list.write_text('\n'.join(name for name, _, _ in keep) + '\n', encoding='utf-8')
result = subprocess.run([r'C:\Program Files\7-Zip\7z.exe', 'x', str(archive),
                         '-o' + str(review), '-i@' + str(file_list), '-scsUTF-8', '-y'],
                        capture_output=True, text=True)
(review / 'extract.log').write_text(result.stdout + result.stderr, encoding='utf-8')
assert result.returncode == 0, result.stdout + result.stderr
unpacked = review / prefix

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

archive_files = {rel: unpacked / rel for _, rel, _ in keep}
current_files = {}
unreadable = []
for directory, dirs, files in os.walk(root):
    dirs[:] = [name for name in dirs if name not in
               {'.git', '.tools', '.venv', 'venv', '__pycache__', '.pytest_cache',
                'node_modules', 'db', 'incremental_db', 'output_files', 'tmp', 'sim'}]
    for filename in files:
        path = Path(directory) / filename
        relative = path.relative_to(root).as_posix()
        if selected(relative):
            try:
                sha(path)
            except OSError as error:
                unreadable.append({'file': relative, 'error': str(error)})
            else:
                current_files[relative] = path
unreadable_names = {item['file'] for item in unreadable}
differences = []
equal = []
for name in sorted(archive_files.keys() | current_files.keys()):
    if name in unreadable_names:
        continue
    archived = archive_files.get(name)
    current = current_files.get(name)
    if archived is None:
        status = 'chi_ban_hien_tai'
    elif current is None:
        status = 'chi_ban_rar'
    elif sha(archived) != sha(current):
        status = 'khac_noi_dung'
    else:
        equal.append(name)
        continue
    differences.append({'file': name, 'status': status,
                        'rar_sha256': sha(archived) if archived else None,
                        'current_sha256': sha(current) if current else None})
report = {'archive': str(archive), 'archive_sha256': sha(archive),
          'extracted_root': str(unpacked), 'equal_count': len(equal),
          'equal_files': equal, 'differences': differences,
          'counts': dict(Counter(item['status'] for item in differences)),
          'unreadable_current_files': unreadable}
(review / 'comparison.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('Giống từng byte:', len(equal))
print('Khác biệt:', report['counts'])
print('Tệp hiện tại không đọc được trên Windows:', len(unreadable))
for item in differences[:100]:
    print(item['status'], item['file'])
