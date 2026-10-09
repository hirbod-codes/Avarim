import { PassThrough, Transform, TransformCallback } from "stream";

export function teeStream() {
    const streams: PassThrough[] = [];

    function isLive(s: PassThrough) {
        return !s.destroyed && !s.writableEnded;
    }

    const splitter = new Transform({
        transform(chunk, _enc, cb: TransformCallback) {
            const live = streams.filter(isLive);

            if (live.length === 0) {
                cb(null, chunk);
                return;
            }

            let pending = live.length;
            let settled = false;

            const done = () => {
                if (settled) return;
                settled = true;
                cb(null, chunk);
            };

            const onBranchReady = () => {
                pending -= 1;
                if (pending === 0) done();
            };

            for (const s of live) {
                const cleanup = () => {
                    s.removeListener('drain', onDrain);
                    s.removeListener('close', onCloseOrError);
                    s.removeListener('error', onCloseOrError);
                };
                const onDrain = () => { cleanup(); onBranchReady(); };
                const onCloseOrError = () => { cleanup(); onBranchReady(); };

                let wrote = false;
                try {
                    wrote = s.write(chunk);
                } catch {
                    // stream was destroyed mid-flight; don't count on it further
                    onBranchReady();
                    continue;
                }

                if (wrote) {
                    onBranchReady();
                } else {
                    s.once('drain', onDrain);
                    s.once('close', onCloseOrError);
                    s.once('error', onCloseOrError);
                }
            }
        },
        final(cb) {
            for (const s of streams) {
                if (isLive(s)) s.end();
            }
            cb();
        },
        destroy(err, cb) {
            for (const s of streams) {
                if (!s.destroyed) s.destroy(err ?? undefined);
            }
            cb(err);
        }
    });

    const createBranch = () => {
        const pt = new PassThrough();
        pt.on('error', () => { });
        streams.push(pt);
        return pt;
    };

    return {
        splitter,
        createBranch
    };
}