// import { EssentiaWASM, Essentia } from "essentia.js";

// export async function analyzeAudio(pcm: Float32Array) {
//     const essentia = new Essentia(EssentiaWASM);

//     const FRAME_SIZE = 4096;
//     const HOP_SIZE = 2048;

//     let loudnessValues: number[] = [];

//     for (let i = 0; i < pcm.length - FRAME_SIZE; i += HOP_SIZE) {
//         const frame = pcm.slice(i, i + FRAME_SIZE);

//         const vector = essentia.arrayToVector(frame);

//         const l = essentia.Loudness(vector);
//         loudnessValues.push(l.loudness);

//         // ✅ safe cleanup
//         if (typeof vector.delete === "function") {
//             vector.delete();
//         }
//     }

//     const avgLoudness =
//         loudnessValues.reduce((a, b) => a + b, 0) / loudnessValues.length;

//     // 🔥 short sample for heavy ops
//     const shortSample = pcm.slice(0, 44100 * 10);
//     const shortVec = essentia.arrayToVector(shortSample);

//     const rhythm = essentia.RhythmExtractor2013(shortVec);
//     const key = essentia.KeyExtractor(shortVec);

//     if (typeof shortVec.delete === "function") {
//         shortVec.delete();
//     }

//     return {
//         bpm: rhythm.bpm,
//         beats: rhythm.beats,
//         key: key.key,
//         scale: key.scale,
//         loudness: avgLoudness,
//     };
// }