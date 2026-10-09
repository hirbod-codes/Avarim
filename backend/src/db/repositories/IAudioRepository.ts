import { Audio } from "../models/Audio";

export interface IAudioRepository {
    get(audioId: string, userId: string): Promise<Audio & { _id: any }>
}