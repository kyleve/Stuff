// Compare Markdown structure after Linear's editor normalizes its serialization.
import { readFileSync } from 'node:fs';
import { fromMarkdown } from 'mdast-util-from-markdown';

function semantic(node) {
  if (Array.isArray(node)) {
    const children = node.flatMap(child => ['strong', 'emphasis'].includes(child.type)
      ? semantic(child.children) : [semantic(child)]);
    return children.reduce((result, child) => {
      const previous = result.at(-1);
      if (previous?.type === 'text' && child.type === 'text') previous.value += child.value;
      else result.push(child);
      return result;
    }, []);
  }
  if (node === null || typeof node !== 'object') return node;
  return Object.fromEntries(Object.entries(node)
    .filter(([key]) => key !== 'position' && key !== 'spread')
    .map(([key, value]) => [key,
      key === 'value' && node.type === 'text' ? value.replace(/\r?\n/g, ' ') : semantic(value)]));
}

const [expected, actual] = JSON.parse(readFileSync(0, 'utf8'));
const left = semantic(fromMarkdown(expected));
const right = semantic(fromMarkdown(actual));
process.stdout.write(JSON.stringify(left) === JSON.stringify(right) ? 'equal\n' : 'different\n');
