# Recovers the destroyed Chat.ets from the ArkTS compiler cache.
# The cache file (Chat.ts, transformed by ets-loader) preserves every field,
# decorator, method and the original line numbers; only the declarative UI
# trees were lowered to imperative observeComponentCreation2 calls. This tool
# converts those trees back to declarative syntax and reassembles the file.
import io
import re

TF = 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug/entry/src/main/ets/screens/Chat.ts'
BROKEN = 'entry/src/main/ets/screens/Chat.ets'
OUT = 'entry/src/main/ets/screens/Chat.ets'


def find_close(text, start):
    """start points at '{'; return the index of its matching '}'."""
    depth = 0
    i = start
    n = len(text)
    instr = None
    while i < n:
        c = text[i]
        if instr is not None:
            if c == instr:
                instr = None
        elif c in '"\'':
            instr = c
        elif c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError('no closing brace')


def find_call_end(text, start):
    """start points at '('; return the index just past its matching ')'."""
    depth = 0
    i = start
    n = len(text)
    instr = None
    while i < n:
        c = text[i]
        if instr is not None:
            if c == instr:
                instr = None
        elif c in '"\'':
            instr = c
        elif c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError('no closing paren')


class Node:
    def __init__(self, kind, name, args=None, children=None, attrs=None, extra=None):
        self.kind = kind          # 'component' | 'custom' | 'if' | 'foreach' | 'text'
        self.name = name
        self.args = args          # create args (raw)
        self.children = children or []
        self.attrs = attrs or []  # raw attribute args, in order
        self.extra = extra        # for 'if': [(cond, body-node-list)], final else list
        self.items = None         # for foreach
        self.keygen = None


class RawNode:
    def __init__(self, text):
        self.text = text


class Decompiler:
    def __init__(self):
        self.out = []
        self.indent = 0

    def w(self, text):
        for line in text.split('\n'):
            self.out.append(('    ' * self.indent + line).rstrip())

    # ---- statement sequence parser -----------------------------------------
    def seq(self, text):
        """Parses statements; returns nodes + stray pops handling via stack."""
        stack = []  # open container nodes
        roots = []
        pos = 0
        n = len(text)
        while pos < n:
            if text[pos:].strip() == '':
                pos = n
                break
            stripped = text[pos:].lstrip()
            # pop belonging to an open container
            mp = re.match(r'(\w+)\.pop\(\);\s*', stripped)
            if mp:
                name = mp.group(1)
                if stack and stack[-1].name == name:
                    node = stack.pop()
                    (stack[-1].children if stack else roots).append(node)
                    pos += len(text[pos:]) - len(stripped) + len(mp.group(0))
                    continue
                if stack:
                    # closes an outer container
                    node = stack.pop()
                    (stack[-1].children if stack else roots).append(node)
                    continue
                pos = n
                break
            # component creation block
            if stripped.startswith('this.observeComponentCreation2((elmtId, isInitialRender) => {'):
                arrow = text.index('=> {', pos) + 3
                bend = find_close(text, arrow)
                cm = re.match(r'\s*, (\w+)\);', text[bend + 1:])
                if cm is None:
                    cm2 = re.match(r'\s*, \{ name: "(\w+)" \}\);', text[bend + 1:])
                    if cm2 is None:
                        raise ValueError('unknown block close at %d: %r' % (pos, text[bend + 1:bend + 80]))
                    pos = bend + 1 + cm2.end()
                    node = self.parse_custom(text[arrow + 1:bend], cm2.group(1))
                    if stack:
                        stack[-1].children.append(node)
                    else:
                        roots.append(node)
                    continue
                name = cm.group(1)
                pos = bend + 1 + cm.end()
                inner = text[arrow + 1:bend]
                if 'If.create();' in inner:
                    node = self.parse_if(inner, name)
                    if stack:
                        stack[-1].children.append(node)
                    else:
                        roots.append(node)
                    continue
                if 'ForEach.create();' in inner:
                    node = self.parse_foreach(inner, name)
                    if stack:
                        stack[-1].children.append(node)
                    else:
                        roots.append(node)
                    continue
                m = re.search(r'(\w+)\.create\(', inner)
                if m is None:
                    continue
                node = Node('component', m.group(1), args=self.create_args(inner, m.group(1)))
                if stack:
                    stack[-1].children.append(node)
                stack.append(node)
                continue
            # attribute statement
            ma = re.match(r'(\w+)\.(\w+)\((.*?)\);\s*(?=\n|$)', text[pos:], re.S)
            if ma is None:
                # multi-line attribute: read until balanced
                acc = ''
                k = pos
                while k < n:
                    nl = text.find('\n', k)
                    line_end = nl if nl >= 0 else n
                    acc += text[k:line_end] + '\n'
                    if acc.rstrip().endswith(';') and acc.count('(') == acc.count(')') and acc.count('{') == acc.count('}'):
                        pos = line_end + 1
                        break
                    k = line_end + 1
                ma = re.match(r'(\w+)\.(\w+)\((.*?)\);\s*$', acc, re.S)
                if ma is None:
                    # plain TypeScript statement inside a generator lambda: copy through
                    if stack:
                        stack[-1].children.append(RawNode(acc.rstrip()))
                    pos = line_end + 1
                    continue
                if stack:
                    stack[-1].attrs.append(ma.group(2) + '(' + ma.group(3) + ')')
                continue
            if stack:
                stack[-1].attrs.append(ma.group(2) + '(' + ma.group(3) + ')')
            pos += len(text[pos:]) - len(stripped) + len(ma.group(0))
            continue
        # close any remaining containers
        while stack:
            node = stack.pop()
            (stack[-1].children if stack else roots).append(node)
        return roots

    def create_args(self, inner, name):
        m = re.search(re.escape(name) + r'\.create\((.*?)\);\n', inner, re.S)
        if m is None:
            m = re.search(re.escape(name) + r'\.create\((.*)\);\s*$', inner, re.S)
        return m.group(1).strip() if m else ''

    def parse_custom(self, inner, name):
        m = re.search(r'new ' + name + r'\(this, \{', inner)
        bstart = inner.index('{', m.start() + len('new ' + name + '(this, ') - 1)
        bend = find_close(inner, bstart)
        params = inner[bstart + 1:bend]
        return Node('custom', name, args=params)

    def parse_if(self, inner, name):
        branches = []
        final_else = []
        pos = 0
        # first condition
        m = re.search(r'if \((.*?)\) \{\s*this\.ifElseBranchUpdateFunction\(0, \(\) => \{', inner, re.S)
        if m is None:
            raise ValueError('if chain not found')
        cond = m.group(1)
        arrow = inner.index('this.ifElseBranchUpdateFunction(0, () => {') + len('this.ifElseBranchUpdateFunction(0, () => {')
        bstart = inner.index('{', arrow - 1)
        bend = find_close(inner, bstart)
        branches.append((cond, self.seq(inner[bstart + 1:bend])))
        pos = bend + 1
        rest = inner[pos:]
        while True:
            em = re.match(r'\s*else if \((.*?)\) \{\s*this\.ifElseBranchUpdateFunction\((\d+), \(\) => \{', rest, re.S)
            if em:
                cond2 = em.group(1)
                arrow2 = rest.index('this.ifElseBranchUpdateFunction(' + em.group(2) + ', () => {') + len('this.ifElseBranchUpdateFunction(' + em.group(2) + ', () => {')
                b2 = rest.index('{', arrow2 - 1)
                e2 = find_close(rest, b2)
                branches.append((cond2, self.seq(rest[b2 + 1:e2])))
                rest = rest[e2 + 1:]
                continue
            em = re.match(r'\s*else \{\s*this\.ifElseBranchUpdateFunction\((\d+), \(\) => \{', rest, re.S)
            if em:
                num = em.group(1)
                arrow2 = rest.index('this.ifElseBranchUpdateFunction(' + num + ', () => {') + len('this.ifElseBranchUpdateFunction(' + num + ', () => {')
                b2 = rest.index('{', arrow2 - 1)
                e2 = find_close(rest, b2)
                final_else = self.seq(rest[b2 + 1:e2])
                rest = rest[e2 + 1:]
            break
        return Node('if', 'If', children=branches, extra=final_else)

    def parse_foreach(self, inner, name):
        # item generator: const forEachItemGenFunction = (args) => { ... }  — or
        # the single-argument form without parens: const forEachItemGenFunction = _item => { ... }
        m = re.search(r'const (\w+) = \((\w+)(?::\s*[\w\[\]]+)?\) => \{', inner)
        if m is None:
            m = re.search(r'const (\w+) = (\w+) => \{', inner)
            if m is None:
                raise ValueError('foreach generator not found')
            gen_name = m.group(1)
            gen_args = m.group(2)
        else:
            gen_name = m.group(1)
            gen_args = m.group(2)
        bstart = inner.index('{', m.start() + len(m.group(0)) - 1)
        bend = find_close(inner, bstart)
        children = self.seq(inner[bstart + 1:bend])
        # items + keygen from the call
        cm = re.search(r'this\.forEachUpdateFunction\(elmtId, (.*?), ' + gen_name + r', \(([\w: ,\.\[\]]*)\)\s*(?::\s*\w+)?\s*=> (.+?)(?:, \w+)*\);\s*$', inner, re.S)
        if cm is None:
            cm = re.search(r'this\.forEachUpdateFunction\(elmtId, (.*?), ' + gen_name, inner, re.S)
            items = cm.group(1)
            keygen = None
        else:
            items = cm.group(1)
            keygen = '(%s) => %s' % (cm.group(2), cm.group(3).rstrip().rstrip(','))
        node = Node('foreach', 'ForEach', children=children)
        node.items = items
        node.keygen = keygen
        node.args = gen_args
        return node

    # ---- emission -----------------------------------------------------------
    def emit_node(self, node):
        if node.kind == 'custom':
            self.w('%s(%s)' % (node.name, node.args))
            return
        if node.kind == 'if':
            first = True
            for cond, body in node.children:
                self.w(('if ' if first else '} else if ') + '(%s) {' % cond)
                self.indent += 1
                self.emit_seq(body)
                self.indent -= 1
                first = False
            if node.extra:
                self.w('} else {')
                self.indent += 1
                self.emit_seq(node.extra)
                self.indent -= 1
            self.w('}')
            return
        if node.kind == 'foreach':
            self.w('ForEach(%s, (%s) => {' % (node.items, node.args))
            self.indent += 1
            self.emit_seq(node.children)
            self.indent -= 1
            if node.keygen:
                self.w('}, %s)' % node.keygen)
            else:
                self.w('})')
            return
        # component
        arg = node.args.strip()
        head = '%s(%s)' % (node.name, arg) if arg else '%s()' % node.name
        if node.children:
            self.w(head + ' {')
            self.indent += 1
            self.emit_seq(node.children)
            self.indent -= 1
            tail = '}'
        else:
            tail = None
            self.w(head)
        if node.attrs:
            for a in node.attrs:
                if tail is not None:
                    self.w(tail + '.' + a)
                    tail = None
                else:
                    self.w('.' + a)
        if tail is not None:
            self.w(tail)

    def emit_seq(self, nodes):
        for node in nodes:
            if isinstance(node, RawNode):
                self.w(node.text.rstrip(';') + ';')
                continue
            self.emit_node(node)


def decompile_method(body):
    d = Decompiler()
    d.emit_seq(d.seq(body))
    return '\n'.join(d.out)


def class_span(lines, class_line):
    """Returns (end_index_exclusive) of the class body: braces from the class line."""
    text = '\n'.join(lines[class_line:])
    end = find_close(text, text.index('{'))
    return class_line + text[:end].count('\n') + 1


def main():
    tf = io.open(TF, encoding='utf-8').read()
    lines = tf.split('\n')

    def find_class(name):
        for i, line in enumerate(lines):
            if re.match(r'\s*(export )?class %s extends ViewV2' % name, line):
                return i
        raise ValueError(name)

    def method_slice(start_line, marker):
        """start_line: index of the method's first line (its '{' is at the end of the previous
        signature line or the same line). Returns the raw body text between the braces."""
        return None

    def class_parts(name):
        ci = find_class(name)
        text = '\n'.join(lines[ci:])
        bend = find_close(text, text.index('{'))
        body = text[text.index('{') + 1:bend]
        return body

    # ---- broken file head: everything before the first '  build() {' ----
    broken = io.open(BROKEN, encoding='utf-8').read()
    # the destructive edit replaced the first build() (GoalBar's) through EOF;
    # the head (imports, helpers, GoalBar fields and methods) is intact.
    head_end = broken.index('  build() {')
    head = broken[:head_end].rstrip() + '\n'

    # ---- strip class boilerplate from a transformed class body ----
    def strip_boilerplate(body, name):
        # remove constructor / resetStateVarsOnReuse / updateStateVars / rerender
        for marker in ('constructor(parent, params', 'public resetStateVarsOnReuse(params', 'public updateStateVars(params', 'rerender() {'):
            m = re.search(r'\n    ' + re.escape(marker), body)
            if m is None:
                continue
            bstart = body.index('{', m.start())
            bend = find_close(body, bstart)
            body = body[:m.start()] + body[bend + 1:]
        # remove the class's own imperative UI methods (they get re-decompiled):
        # find methods that contain observeComponentCreation2
        removed = []
        while True:
            m = re.search(r'\n    (\w+)\(parent = null\) \{', body)
            if m is None:
                break
            bstart = body.index('{', m.start())
            bend = find_close(body, bstart)
            if 'observeComponentCreation2' in body[bstart:bend + 1]:
                removed.append((m.group(1), body[bstart + 1:bend]))
                body = body[:m.start()] + body[bend + 1:]
                continue
            break
        # initialRender
        m = re.search(r'\n    initialRender\(\) \{', body)
        bstart = body.index('{', m.start())
        bend = find_close(body, bstart)
        initial_body = body[bstart + 1:bend]
        body = body[:m.start()] + body[bend + 1:]
        return body, initial_body, removed

    # ---- build the recovered file ----
    out = []
    out.append('// Recovered from the ArkTS compiler cache after an accidental overwrite:')
    out.append('// GoalBar / BlockedCard / ComputerCards / Chat with their original fields,')
    out.append('// methods and de-compiled UI trees.')
    out.append('')

    head = head.replace('\n', '\n')
    # head currently ends with the GoalBar method definitions; keep as is
    out.append(head)

    order = ['GoalBar', 'BlockedCard', 'ComputerCards', 'Chat']
    for name in order:
        body = class_parts(name)
        body, initial_body, removed = strip_boilerplate(body, name)
        export = 'export ' if name == 'Chat' else ''
        out.append('')
        out.append('@ComponentV2')
        out.append('%sstruct %s {' % (export, name))
        out.append(body.strip('\n'))
        if name == 'Chat':
            # decompile the builders + build
            for bname, bbody in removed:
                out.append('')
                out.append('    %s() {' % bname)
                out.append(decompile_method(bbody))
                out.append('    }')
            out.append('')
            out.append('    build() {')
            out.append(decompile_method(initial_body))
            out.append('    }')
        else:
            out.append('')
            out.append('    build() {')
            out.append(decompile_method(initial_body))
            out.append('    }')
        out.append('}')

    io.open(OUT, 'w', encoding='utf-8', newline='\n').write('\n'.join(out))
    print('recovered Chat.ets written, lines:', len('\n'.join(out).split('\n')))


main()
