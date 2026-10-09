export class MinFileSizeNotMetError extends Error {
    constructor(public readonly limit: number, public readonly actual: number) {
        super(`File size of ${actual} bytes did not meet minimum of ${limit} bytes`);
        this.name = "MinFileSizeNotMetError";
    }
}
