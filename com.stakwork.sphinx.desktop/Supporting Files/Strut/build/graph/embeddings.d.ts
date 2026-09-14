import { type Bolt } from "./bolt.js";
import type { Embedder } from "./node-writer.js";
export declare const EMBEDDING_MODEL = "Xenova/all-MiniLM-L6-v2";
export declare const EMBEDDING_DIM = 384;
export declare const EMBEDDING_MAX_TOKENS = 256;
export interface MiniLMOptions {
    /** HF repo id of an ONNX export of all-MiniLM-L6-v2. */
    model?: string;
    /** Where model files are cached. See src/model-dir.ts for the default
     *  (`STRUT_MODEL_DIR`, `STRUT_MODEL_CACHE`, or `<cache root>/strut/models`). */
    cacheDir?: string;
    /** Texts per forward pass. */
    batchSize?: number;
}
export declare class MiniLMEmbedder implements Embedder {
    private readonly tf;
    private readonly tokenizer;
    private readonly model;
    private readonly cls;
    private readonly sep;
    private readonly pad;
    private readonly batchSize;
    private constructor();
    /** Load (downloading on first use) and self-check the output dimension. */
    static load(opts?: MiniLMOptions): Promise<MiniLMEmbedder>;
    embed(texts: string[]): Promise<number[][]>;
    /**
     * Tokenize like sentence-transformers: the 256 cap INCLUDES [CLS]/[SEP],
     * so the body is cut to 254 and the specials are always present.
     * (transformers.js's own `truncation: true` truncates after adding
     * specials and chops [SEP] off long inputs — measurably different
     * vectors.) Right-padded with the pad id; mask 1 on real tokens.
     */
    private encodeBatch;
    private forward;
}
/** Mean pooling over the attention mask, then L2 normalization — exactly
 *  sentence-transformers' `Pooling(mean)` + `Normalize`. */
export declare function meanPoolNormalize(hidden: Float32Array, dims: number[], mask: ArrayLike<number | bigint>): number[][];
export declare function cosine(a: number[], b: number[]): number;
export interface BackfillReport {
    /** Nodes whose `text_embeddings` was filled. */
    text_embeddings: number;
    /** Per `{stem}_embeddings` column, nodes filled. */
    vector_fields: Record<string, number>;
}
/**
 * Crash-safe sweep: embed every Strut node whose search text exists but
 * whose vector is NULL, in batches, until none remain. Idempotent and cheap
 * when clean. Run at every boot of the graph backend. Also covers the
 * per-property `{stem}_embeddings` of the `vector_index` types.
 */
export declare function backfillEmbeddings(bolt: Bolt, embedder: Embedder, batchSize?: number): Promise<BackfillReport>;
