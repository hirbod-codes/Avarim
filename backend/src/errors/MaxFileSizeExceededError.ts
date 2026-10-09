export class MaxFileSizeExceededError extends Error {
    constructor(public readonly limit: number, public readonly actual: number) {
        super(`File size exceeded limit of ${limit} bytes (received ${actual} bytes)`);
        this.name = "MaxFileSizeExceededError";
    }
}
