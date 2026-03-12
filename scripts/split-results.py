#!/usr/bin/env python3
"""
split-results.py — 將 Cloudflare /crawl 的 JSON 結果拆成個別 Markdown 檔案

用法:
    python scripts/split-results.py results/crawl-20260312-143000.json
    python scripts/split-results.py results/crawl-20260312-143000.json --output-dir docs/
    python scripts/split-results.py results/crawl-20260312-143000.json --format html
"""

import json
import os
import re
import sys
import argparse
from pathlib import Path
from urllib.parse import urlparse


def sanitize_filename(name: str, max_length: int = 80) -> str:
    """將字串轉成安全的檔案名稱"""
    # 移除或替換不安全字元
    name = re.sub(r'[<>:"/\\|?*]', '-', name)
    name = re.sub(r'\s+', '-', name)
    name = re.sub(r'-+', '-', name)
    name = name.strip('-. ')
    # 截斷
    if len(name) > max_length:
        name = name[:max_length].rstrip('-')
    return name or 'untitled'


def url_to_filename(url: str) -> str:
    """將 URL 轉成檔案名稱"""
    parsed = urlparse(url)
    path = parsed.path.strip('/')
    if not path:
        return sanitize_filename(parsed.netloc)
    return sanitize_filename(path.replace('/', '-'))


def split_results(input_file: str, output_dir: str, fmt: str = 'markdown') -> dict:
    """
    讀取 crawl 結果 JSON，將每一頁存成獨立檔案。

    回傳統計資訊。
    """
    with open(input_file, 'r', encoding='utf-8') as f:
        data = json.load(f)

    records = data.get('result', {}).get('records', [])
    if not records:
        print('找不到 records，請確認 JSON 格式正確')
        return {'total': 0, 'saved': 0, 'skipped': 0}

    os.makedirs(output_dir, exist_ok=True)

    stats = {'total': len(records), 'saved': 0, 'skipped': 0}
    seen_filenames = set()

    for record in records:
        if record.get('status') != 'completed':
            stats['skipped'] += 1
            continue

        url = record.get('url', '')
        title = record.get('metadata', {}).get('title', '')
        content = record.get(fmt, record.get('markdown', record.get('html', '')))

        if not content:
            stats['skipped'] += 1
            continue

        # 決定檔案名稱
        base_name = url_to_filename(url)

        # 避免重複
        filename = base_name
        counter = 1
        while filename in seen_filenames:
            filename = f'{base_name}-{counter}'
            counter += 1
        seen_filenames.add(filename)

        # 副檔名
        ext = '.md' if fmt == 'markdown' else '.html' if fmt == 'html' else '.json'
        filepath = os.path.join(output_dir, f'{filename}{ext}')

        # 寫入（markdown 加 frontmatter）
        with open(filepath, 'w', encoding='utf-8') as f:
            if fmt == 'markdown':
                f.write(f'---\n')
                f.write(f'title: "{title}"\n')
                f.write(f'url: "{url}"\n')
                f.write(f'status: {record.get("metadata", {}).get("status", "")}\n')
                f.write(f'---\n\n')
            f.write(content)

        stats['saved'] += 1

    return stats


def main():
    parser = argparse.ArgumentParser(
        description='將 Cloudflare /crawl 結果拆成個別檔案'
    )
    parser.add_argument('input', help='crawl 結果的 JSON 檔案路徑')
    parser.add_argument(
        '--output-dir', '-o',
        default='pages',
        help='輸出目錄 (預設: pages/)'
    )
    parser.add_argument(
        '--format', '-f',
        choices=['markdown', 'html', 'json'],
        default='markdown',
        help='輸出格式 (預設: markdown)'
    )

    args = parser.parse_args()

    if not os.path.exists(args.input):
        print(f'錯誤: 找不到 {args.input}')
        sys.exit(1)

    print(f'讀取: {args.input}')
    print(f'輸出: {args.output_dir}/')
    print(f'格式: {args.format}')
    print()

    stats = split_results(args.input, args.output_dir, args.format)

    print(f'完成!')
    print(f'  總共:   {stats["total"]} 頁')
    print(f'  已存:   {stats["saved"]} 個檔案')
    print(f'  跳過:   {stats["skipped"]} 頁')
    print(f'  位置:   {args.output_dir}/')


if __name__ == '__main__':
    main()
