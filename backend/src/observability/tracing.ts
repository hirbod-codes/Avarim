// -----------------------------------------------------------------------------
// This file MUST be loaded before anything else in the process — before
// express, mongodb, http, or any instrumented module is imported. OTel's
// auto-instrumentation works by monkey-patching modules the moment they're
// require()'d; if express loads first, its patches never apply.
//
// CRITICAL: this file must NOT import anything from the app's own module
// graph (no `from '..'`, no `from './configs'`, nothing under src/ that
// isn't purely local to observability). Because this loads via --require
// before the app's real entry point runs, importing '..' (which resolves
// to src/index.ts — the entry point itself) causes the whole app to boot
// as a side effect of loading THIS file, and then boot AGAIN when ts-node
// runs src/index.ts as the actual entry script — two full app instances
// in one process (double Mongo connections, double cron jobs, double
// Express listen -> EADDRINUSE). Read env vars directly via process.env
// here, never via the app's config module.
//
// Wire it in via NODE_OPTIONS or a --require flag, NOT via a normal import
// at the top of app.ts:
//
//   node --require ./dist/observability/tracing.js dist/index.js
//
// or in package.json:
//   "start": "node --require ./dist/observability/tracing.js dist/index.js"
//
// If your build targets ESM (tsconfig "module": "nodenext"/"esnext"), swap
// --require for --import, and see the ESM note in the README this ships
// with — the require-hook approach above only works for CommonJS output.
// -----------------------------------------------------------------------------

// import { join } from 'path';
import dotenv from 'dotenv';
// This file loads before configs.ts ever gets a chance to call
// dotenv.config() itself, so it needs its own call here — otherwise
// process.env.OTEL_EXPORTER_OTLP_ENDPOINT may not be populated yet.
dotenv.config();

import { NodeSDK } from '@opentelemetry/sdk-node';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { resourceFromAttributes } from '@opentelemetry/resources';
import {
    ATTR_SERVICE_NAME,
    ATTR_SERVICE_VERSION,
    ATTR_DEPLOYMENT_ENVIRONMENT_NAME,
} from '@opentelemetry/semantic-conventions';

const otelExporterOtlpEndpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT;
console.log('tracing otelExporterOtlpEndpoint:', otelExporterOtlpEndpoint);
if (!otelExporterOtlpEndpoint) {
    throw new Error('The OTEL_EXPORTER_OTLP_ENDPOINT environment variable is not provided');
}

const sdk = new NodeSDK({
    resource: resourceFromAttributes({
        [ATTR_SERVICE_NAME]: 'avarim-backend',
        [ATTR_SERVICE_VERSION]: process.env.AVARIM_BACKEND_VERSION ?? 'unknown',
        [ATTR_DEPLOYMENT_ENVIRONMENT_NAME]: process.env.NODE_ENV ?? 'development',
    }),

    traceExporter: new OTLPTraceExporter({
        url: `${otelExporterOtlpEndpoint}/v1/traces`,
        timeoutMillis: 5000,
    }),

    instrumentations: [
        getNodeAutoInstrumentations({
            // Instruments express, http, mongodb, aws-sdk (S3), dns, etc. out of
            // the box. Disable the noisy/low-value ones explicitly rather than
            // letting them flood every trace:
            '@opentelemetry/instrumentation-fs': { enabled: false },
            '@opentelemetry/instrumentation-http': {
                // Don't create spans for Prometheus scraping your own /metrics,
                // or for Docker/nginx health checks against /healthz.
                ignoreIncomingRequestHook: (req) =>
                    req.url === '/metrics' || req.url === '/healthz' || req.url === '/readyz',
            },
        }),
    ],
});

sdk.start();

// Flush any pending spans before the process actually exits, instead of
// silently dropping the last batch on a container restart/redeploy.
const FORCE_EXIT_MS = 5000;
for (const signal of ['SIGTERM', 'SIGINT'] as const) {
    process.on(signal, () => {
        const forceExit = setTimeout(() => {
            console.error(`shutdown did not finish within ${FORCE_EXIT_MS}ms — forcing exit`);
            process.exit(1);
        }, FORCE_EXIT_MS);

        sdk
            .shutdown()
            .catch((err) => console.error('otel shutdown error', err))
            .finally(() => {
                clearTimeout(forceExit);
                process.exit(0);
            });
    });
}