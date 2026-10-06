#!/usr/bin/env python3
"""Ask the local LM Studio model for text, to save paid tokens on bulk writing. Standard library only.

    python tools/local_llm.py "Write 20 short news headlines ..." --out build/news.txt

LM Studio (or Bionic's server) must be running on http://localhost:1234 with qwen/qwen3.5-9b loaded.
Qwen3.5 is a thinking model, but LM Studio accepts "reasoning_effort": "none", which turns thinking off (found by testing: 0 reasoning
tokens, answers in seconds). That is the default here; pass --think to let it reason (slow: thousands of hidden tokens, about 20 per second).
Good for: microcopy, headline templates, drafts.
Not good for: facts (it invents them), Swift or SwiftUI code (it gets Swift 6 wrong). Always read what it writes.
"""
import argparse
import json
import sys
import urllib.request

URL = 'http://localhost:1234/v1/chat/completions'
MODEL = 'qwen/qwen3.5-9b'

HOUSE_STYLE = (
    'You write short in-game text for a retro pixel-art airline game. Plain, specific, friendly. '
    'Never use em dashes, emoji, exclamation marks, hype words, or made-up statistics. Use only plain ASCII characters.'
)


def ask(prompt, system=HOUSE_STYLE, max_tokens=4000, temperature=0.7, timeout=1800, think=False):
    body = {
        'model': MODEL,
        'messages': [{'role': 'system', 'content': system}, {'role': 'user', 'content': prompt}],
        'max_tokens': max_tokens,
        'temperature': temperature,
    }
    if not think:
        body['reasoning_effort'] = 'none'
    request = urllib.request.Request(URL, data=json.dumps(body).encode('utf-8'), headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        reply = json.load(response)
    message = reply['choices'][0]['message']
    text = (message.get('content') or '').strip()
    if not text:
        raise RuntimeError('empty answer: with --think the model may have used the whole budget reasoning; raise max_tokens')
    return text


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('prompt')
    parser.add_argument('--out', help='write the answer to this file instead of printing it')
    parser.add_argument('--max-tokens', type=int, default=4000)
    parser.add_argument('--think', action='store_true', help='let the model reason first (slow)')
    parser.add_argument('--temperature', type=float, default=0.7)
    args = parser.parse_args()
    text = ask(args.prompt, max_tokens=args.max_tokens, temperature=args.temperature, think=args.think)
    if args.out:
        with open(args.out, 'w', encoding='utf-8') as f:
            f.write(text + '\n')
        print(f'wrote {len(text)} characters to {args.out}')
    else:
        sys.stdout.buffer.write((text + '\n').encode('utf-8'))


if __name__ == '__main__':
    main()
