import type { Server } from 'node:http';
import { getLogger } from '../observability/requestLoggerContext';

/**
 * Last line of defense — NOT a substitute for proper try/catch or the
 * centralized Express error handler. Their only job is to guarantee
 * nothing is ever lost silently before the process goes down.
 *
 * uncaughtException / unhandledRejection mean the process is in an
 * unknown state (a genuine bug slipped past everything else). The
 * correct move is: log it with everything you have, stop accepting new
 * connections, let in-flight requests finish (bounded by a timeout),
 * then exit — and let Docker Swarm / PM2 / k8s restart the process clean.
 * Do NOT try to keep serving traffic after this fires.
 */
export function registerProcessErrorHandlers(server: Server): void {
    const log = getLogger().child({ module: 'error', middleware: 'registerProcessErrorHandlers' });

    let shuttingDown = false;

    function shutdown(reason: string, err: unknown): void {
        if (shuttingDown) return;
        shuttingDown = true;

        log.fatal({ err, reason }, 'Fatal error — shutting down process');

        // Stop accepting new connections; let in-flight ones drain.
        server.close(() => {
            process.exit(1);
        });

        // Hard exit if graceful shutdown hangs (e.g. a connection never closes).
        setTimeout(() => {
            log.fatal('Forced shutdown after timeout — graceful close did not complete');
            process.exit(1);
        }, 10_000).unref();
    }

    process.on('uncaughtException', (err) => {
        shutdown('uncaughtException', err);
    });

    process.on('unhandledRejection', (reason) => {
        shutdown('unhandledRejection', reason);
    });

    // Not errors, but worth wiring alongside — Docker Swarm sends SIGTERM
    // on service update/scale-down; handle it the same way for clean
    // rolling deploys instead of connections being cut mid-request.
    process.on('SIGTERM', () => {
        log.info('SIGTERM received — starting graceful shutdown');
        server.close(() => process.exit(0));
    });
}