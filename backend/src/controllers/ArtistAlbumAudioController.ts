import { WithId } from "../db/common_schemas";
import { Album } from "../db/models/Album";
import { Artist } from "../db/models/Artist";
import { Audio } from "../db/models/Audio";
import ArtistAlbumAudioRepository from "../db/MongoDB/ArtistAlbumAudioRepository";
import { getLogger, runWithLogger } from "../observability/requestLoggerContext";

export class ArtistAlbumAudioCreationError extends Error { }

export class ArtistAlbumAudioController {
    async create(artistId: undefined | string, albumId: undefined | string, audioId: string, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<void> {
        const log = getLogger().child({ class: 'ArtistAlbumAudioController', method: 'create' })

        artistAlbumAudioRepository ??= new ArtistAlbumAudioRepository()

        const result = await runWithLogger(log, artistAlbumAudioRepository.insert({ artistId, albumId, audioId }))
        log.debug({ result })
        if (!result.acknowledged) {
            log.info('failed to create a artistAlbumAudio')
            throw new ArtistAlbumAudioCreationError()
        }
    }

    // Artists

    async getArtistAlbums(artistId: string, skip: number, limit: number, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<WithId<Album>[]> {
        const log = getLogger().child({ class: 'ArtistAlbumAudioController', method: 'getArtistAlbums' })

        artistAlbumAudioRepository ??= new ArtistAlbumAudioRepository()

        return await runWithLogger(log, artistAlbumAudioRepository.getManyAlbumByArtistId(artistId, skip, limit))
    }

    async getArtistAudios(artistId: string, skip: number, limit: number, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<WithId<Audio>[]> {
        const log = getLogger().child({ class: 'ArtistAlbumAudioController', method: 'getArtistAudios' })

        artistAlbumAudioRepository ??= new ArtistAlbumAudioRepository()

        return await runWithLogger(log, artistAlbumAudioRepository.getManyAudioByArtistId(artistId, skip, limit))
    }

    // Albums

    async getAlbumArtists(albumId: string, skip: number, limit: number, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<WithId<Artist>[]> {
        const log = getLogger().child({ class: 'ArtistAlbumAudioController', method: 'getAlbumArtists' })

        artistAlbumAudioRepository ??= new ArtistAlbumAudioRepository()

        return await runWithLogger(log, artistAlbumAudioRepository.getManyArtistByAlbumId(albumId, skip, limit))
    }

    async getAlbumAudios(albumId: string, skip: number, limit: number, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<WithId<Audio>[]> {
        const log = getLogger().child({ class: 'ArtistAlbumAudioController', method: 'getAlbumAudios' })

        artistAlbumAudioRepository ??= new ArtistAlbumAudioRepository()

        return await runWithLogger(log, artistAlbumAudioRepository.getManyAudioByAlbumId(albumId, skip, limit))
    }

    // Audios

    async getAudioAlbums(audioId: string, skip: number, limit: number, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<WithId<Album>[]> {
        const log = getLogger().child({ class: 'ArtistAlbumAudioController', method: 'getAudioAlbums' })

        artistAlbumAudioRepository ??= new ArtistAlbumAudioRepository()

        return await runWithLogger(log, artistAlbumAudioRepository.getManyAlbumByAudioId(audioId, skip, limit))
    }

    async getAudioArtists(audioId: string, skip: number, limit: number, artistAlbumAudioRepository?: ArtistAlbumAudioRepository): Promise<WithId<Artist>[]> {
        const log = getLogger().child({ class: 'ArtistAlbumAudioController', method: 'getAudioArtists' })

        artistAlbumAudioRepository ??= new ArtistAlbumAudioRepository()

        return await runWithLogger(log, artistAlbumAudioRepository.getManyArtistByAudioId(audioId, skip, limit))
    }
}