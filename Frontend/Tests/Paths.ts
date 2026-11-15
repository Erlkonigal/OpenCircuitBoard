import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const WorkspaceRoot = fileURLToPath(new URL('../../', import.meta.url));
export const buildPath = (name: string) => path.join(WorkspaceRoot, 'build', name);
