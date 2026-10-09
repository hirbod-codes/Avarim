import { Pushgateway, register } from 'prom-client';
import { isProduction, pushgatewayUrl } from '../configs';
import { logger } from './logger';

export function startMetricsPush() {
    if (isProduction) return;

    const gateway = new Pushgateway(pushgatewayUrl, {}, register);
    const interval = setInterval(() => {
        gateway.pushAdd({ jobName: 'avarim-backend-dev' })
            .catch((err) => logger.warn({ err }, 'pushgateway push failed'));
    }, 15000);
    interval.unref();
}