export declare function initialize(data: {
    entry: string;
}): void;
type ResolveContext = {
    parentURL?: string;
    conditions: string[];
    importAttributes: Record<string, string>;
};
type ResolveResult = {
    url: string;
    format?: string | null;
    shortCircuit?: boolean;
};
type NextResolve = (specifier: string, context: ResolveContext) => Promise<ResolveResult>;
export declare function resolve(specifier: string, context: ResolveContext, next: NextResolve): Promise<ResolveResult>;
export {};
