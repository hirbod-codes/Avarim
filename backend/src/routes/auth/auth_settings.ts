import { AppSettings, AppSettingsUpdate } from "../../db/models/AppSettings";
import AppSettingsRepository from "../../db/MongoDB/AppSettingsRepository";
import { getLogger, runWithLogger } from '../../observability/requestLoggerContext';

const AUTH_SETTINGS_KEY = 'auth';

export async function getAuthSettings(): Promise<AppSettings> {
    const log = getLogger().child({ step: 'getAuthSettings' });

    const repo = new AppSettingsRepository();
    const doc = await runWithLogger(log, () => repo.getByKey(AUTH_SETTINGS_KEY))

    if (!doc) {
        log.info('No auth settings document found, using defaults');
        return { key: 'auth', allowEmailRegistration: true, allowOtp: false } as any;
    }

    return doc
}

export async function updateAuthSettings(patch: AppSettingsUpdate): Promise<AppSettings> {
    const log = getLogger().child({ step: 'updateAuthSettings' });

    log.debug({ patch })

    const repo = new AppSettingsRepository();
    const current = await runWithLogger(log, () => getAuthSettings())
    const merged = { ...current, ...patch };
    log.debug({ current, merged })

    await runWithLogger(log, () => repo.upsertByKey(AUTH_SETTINGS_KEY, merged))
    log.info('Persisted auth settings');

    return merged;
}
