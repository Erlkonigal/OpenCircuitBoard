import { readFileSync } from 'node:fs';
import { inflateRawSync } from 'node:zlib';
import path from 'node:path';
import type { ProjectDocument } from '../Source/Model';
import { WorkspaceRoot } from './Paths';

// These generated fixtures contain project.json as their first deflated ZIP entry.
// Read the committed archive so browser and native assertions share the real layout.
export function exampleProject(name: 'HelloWorld5x8' | 'Ram16x8'): ProjectDocument {
    const bytes = readFileSync(path.join(WorkspaceRoot, 'Frontend/Assets/Examples', name + '.ocb'));
    const nameLength = bytes.readUInt16LE(26), extraLength = bytes.readUInt16LE(28);
    if (bytes.readUInt32LE(0) !== 0x04034b50 || bytes.readUInt16LE(6) !== 0 || bytes.readUInt16LE(8) !== 8
        || bytes.toString('utf8', 30, 30 + nameLength) !== 'project.json') throw Error('Unexpected generated example archive');
    const start = 30 + nameLength + extraLength;
    return JSON.parse(inflateRawSync(bytes.subarray(start, start + bytes.readUInt32LE(18))).toString('utf8')) as ProjectDocument;
}
