export interface Hotword {
    phrase: string;
    /** Per-phrase boost; falls back to the recognizer's global score. */
    score?: number;
}
/** One phrase per line, optional trailing ` :score`, `#` comments, blanks
 *  ignored. The same text format sherpa reads, so a stored list is passed
 *  through verbatim. */
export declare function parseHotwords(text: string): Hotword[];
export declare function formatHotwords(list: readonly Hotword[]): string;
/** Stable id for a compiled list: sha256 of its canonical text. */
export declare function hotwordsHash(list: readonly Hotword[]): string;
/** Sentencepiece-style vocab (`piece\tscore`) from a sherpa `tokens.txt`
 *  (`piece id` per line). Special tokens (`<blk>`, `<sos/eos>`, `<unk>`) are
 *  replaced by the three sentencepiece specials. */
export declare function synthesizeBpeVocab(tokensTxt: string): string;
export interface CompiledHotwords {
    hash: string;
    /** The list, one phrase per line (sherpa `hotwordsFile`). */
    file: string;
    /** The synthesized vocab (sherpa `bpeVocab`). */
    vocab: string;
}
/** Materialize a list beside a model: `<modelDir>/hotwords/<hash>.txt` plus
 *  `<modelDir>/bpe.vocab` (synthesized once). Idempotent. */
export declare function compileHotwords(modelDir: string, list: readonly Hotword[]): Promise<CompiledHotwords>;
export interface HotwordsListInfo {
    name: string;
    count: number;
    updatedAt: string;
}
/** `<dataDir>/audio/hotwords/<name>.txt`. A workflow's `http` step PUTs a
 *  list here; a stream names it in `start.hotwords`. */
export declare class HotwordsStore {
    readonly dir: string;
    constructor(dataDir: string);
    private pathOf;
    list(): Promise<HotwordsListInfo[]>;
    /** The raw text, or null when the list doesn't exist. */
    get(name: string): Promise<string | null>;
    put(name: string, text: string): Promise<Hotword[]>;
    delete(name: string): Promise<boolean>;
}
