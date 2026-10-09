import { boolean, BooleanSchema, InferType, number, NumberSchema, string, StringSchema } from "yup";
import http, { IncomingMessage } from "http";
import https from "https";
import fs from "fs";
import path from "path";
import os from "os";
import { envPrefix, envSuffix, isProduction } from './configs';

const SECRETS_DIR = process.env.SECRETS_DIR ?? '/run/secrets'

function readSecretFile(key: string): string | undefined {
    if (os.platform() !== 'linux')
        return undefined

    const secretPath = path.join(SECRETS_DIR, key)

    try {
        const contents = fs.readFileSync(secretPath, 'utf8').trim()
        return contents.length > 0 ? contents : undefined
    } catch (e: any) {
        if (e?.code !== 'ENOENT')
            console.warn(`Found ${secretPath} but couldn't read it: ${e?.message ?? e}`)
        return undefined
    }
}

function resolveRawEnv(key: string): string | undefined {
    return readSecretFile(`${envPrefix}${key}${envSuffix}`) ?? process.env[key]
}

export function validateBooleanEnv(env?: boolean, message?: string, validateWithYup?: undefined, manuallyValidate?: (env?: boolean) => boolean): boolean
export function validateBooleanEnv<T extends BooleanSchema>(env?: boolean, message?: string, validateWithYup?: (schema: BooleanSchema) => T, manuallyValidate?: (env?: boolean) => boolean): InferType<T>
export function validateBooleanEnv<T extends BooleanSchema>(env?: boolean, message?: string, validateWithYup?: (schema: BooleanSchema) => T, manuallyValidate?: (env?: boolean) => boolean): InferType<T> | boolean {
    let schema: BooleanSchema = boolean()
    if (validateWithYup)
        schema = validateWithYup(schema)
    else
        schema = schema.required()

    if (manuallyValidate !== undefined && manuallyValidate(env) === false)
        throw new Error(message ?? 'Invalid environment variable provided')

    return schema.validateSync(env) as InferType<T> | boolean
}

export function validateStringEnv(env?: string, message?: string, validateWithYup?: undefined, manuallyValidate?: (env?: string) => boolean): string
export function validateStringEnv<T extends StringSchema>(env?: string, message?: string, validateWithYup?: (schema: StringSchema) => T, manuallyValidate?: (env?: string) => boolean): InferType<T>
export function validateStringEnv<T extends StringSchema>(env?: string, message?: string, validateWithYup?: (schema: StringSchema) => T, manuallyValidate?: (env?: string) => boolean): InferType<T> | string {
    let schema: StringSchema = string()
    if (validateWithYup)
        schema = validateWithYup(schema)
    else
        schema = schema.required()

    if (manuallyValidate !== undefined && manuallyValidate(env) === false)
        throw new Error(message ?? 'Invalid environment variable provided')

    return schema.validateSync(env) as InferType<T> | string
}

export function validateIntegerEnv(env?: any, message?: string, validateWithYup?: undefined, manuallyValidate?: (env?: number) => boolean): number
export function validateIntegerEnv<T extends NumberSchema>(env?: any, message?: string, validateWithYup?: (schema: NumberSchema) => T, manuallyValidate?: (env?: number) => boolean): InferType<T>
export function validateIntegerEnv<T extends NumberSchema>(env?: any, message?: string, validateWithYup?: (schema: NumberSchema) => T, manuallyValidate?: (env?: number) => boolean): InferType<T> | number {
    let schema: NumberSchema = number()
    if (validateWithYup)
        schema = validateWithYup(schema)
    else
        schema = schema.required()

    if (manuallyValidate !== undefined && manuallyValidate(env) === false)
        throw new Error(message ?? 'Invalid environment variable provided')

    return schema.validateSync(env) as InferType<T> | number
}

export function getStringEnv(key: string, message?: string, validate?: undefined, manuallyValidate?: (env?: string) => boolean): string
export function getStringEnv<T extends StringSchema>(key: string, message?: string, validate?: (schema: StringSchema) => T, manuallyValidate?: (env?: string) => boolean): InferType<T>
export function getStringEnv<T extends StringSchema>(key: string, message?: string, validate?: (schema: StringSchema) => T, manuallyValidate?: (env?: string) => boolean): InferType<T> | string {
    const resolvedEnv = resolveRawEnv(key)

    console.log({ key, message, resolvedEnv }, `${key}: ${resolvedEnv !== undefined ? (isProduction ? '<*****>' : resolvedEnv) : '<missing>'}`)

    return validateStringEnv(resolvedEnv, message, validate, manuallyValidate)
}

export function getIntegerEnv(key: string, message?: string, validate?: undefined, manuallyValidate?: (env?: number) => boolean): number
export function getIntegerEnv<T extends NumberSchema>(key: string, message?: string, validate?: (schema: NumberSchema) => T, manuallyValidate?: (env?: number) => boolean): InferType<T>
export function getIntegerEnv<T extends NumberSchema>(key: string, message?: string, validate?: (schema: NumberSchema) => T, manuallyValidate?: (env?: number) => boolean): InferType<T> | number {
    const resolvedEnv = resolveRawEnv(key)

    console.log({ key, message, resolvedEnv }, `${key}: ${resolvedEnv !== undefined ? (isProduction ? '<*****>' : resolvedEnv) : '<missing>'}`)

    return validateIntegerEnv(resolvedEnv, message, validate, manuallyValidate)
}

export function getBooleanEnv(key: string, message?: string, validate?: undefined, manuallyValidate?: (env?: boolean) => boolean): boolean
export function getBooleanEnv<T extends BooleanSchema>(key: string, message?: string, validate?: (schema: BooleanSchema) => T, manuallyValidate?: (env?: boolean) => boolean): InferType<T>
export function getBooleanEnv<T extends BooleanSchema>(key: string, message?: string, validate?: (schema: BooleanSchema) => T, manuallyValidate?: (env?: boolean) => boolean): InferType<T> | boolean {
    const raw = resolveRawEnv(key)
    const env = raw?.toLowerCase() === 'true'

    console.log({ key, message, raw, env }, `${key}: ${raw !== undefined ? (isProduction ? '<*****>' : env) : '<missing>'}`)

    validateBooleanEnv(env, message, validate, manuallyValidate)

    return env!
}

export async function httpRequest(options: http.RequestOptions, sendData?: string): Promise<{ response: http.IncomingMessage, data: string }> {
    return new Promise<{ response: http.IncomingMessage, data: string }>((resolve, reject) => {
        const request = http.request(options, (response) => {
            let data = '';
            response.on('data', (chunk) => {
                data += chunk;
            });

            response.on('end', () => {
                resolve({ response, data })
            });

            response.on('error', (e) => {
                console.error(e)
                reject(e)
            });
        });

        request.on('error', (e) => {
            console.error({ e }, `http request failed with error`)
            reject(e)
        });

        if (sendData)
            request.write(sendData);

        request.end();
    })
}

export async function httpsStreamRequest(options: https.RequestOptions, sendData?: string): Promise<IncomingMessage> {
    return new Promise<IncomingMessage>((resolve, reject) => {
        const request = https.request(options, (response) => {
            resolve(response);
        });

        request.on('error', (e) => {
            console.error({ e }, `https stream request failed with error`)
            reject(e)
        });

        if (sendData)
            request.write(sendData);

        request.end();
    })
}

export async function httpsRequest(options: https.RequestOptions, sendData?: string): Promise<{ response: http.IncomingMessage, data: string }> {
    return new Promise<{ response: http.IncomingMessage, data: string }>((resolve, reject) => {
        const request = https.request(options, (response) => {
            let data = '';
            response.on('data', (chunk) => {
                data += chunk;
            });

            response.on('end', () => {
                resolve({ response, data })
            });

            response.on('error', (e) => {
                console.error({ e }, `https request failed with error`)
                reject(e)
            });
        });

        request.on('error', (e) => {
            console.error({ e }, `https request failed with error`)
            reject(e)
        });

        if (sendData)
            request.write(sendData);

        request.end();
    })
}

export async function tryAndWait({ callback, secondsToWait = 5, maxAttempts = 100, onThrow }: { callback: CallableFunction, secondsToWait?: number, maxAttempts?: number, onThrow?: (e: unknown) => void }): Promise<boolean> {
    let attempts = 0

    while (attempts <= maxAttempts) {
        attempts += 1
        console.log('safety', attempts)
        try {
            await callback()
            return true
        }
        catch (e) {
            console.error({ e }, `callback in tryAndWait function throw an error.`)

            onThrow?.(e);

            await (() => new Promise<void>((res, rej) => {
                console.log({ secondsToWait }, `waiting for {secondsToWait} seconds...`)
                setTimeout(() => { res() }, secondsToWait * 1000)
            }))()
        }
    }

    if (attempts > 100) {
        console.log('safety reached!!')
        return false
    }

    return true
}

export function streamToBuffer(stream: NodeJS.ReadableStream): Promise<Buffer> {
    return new Promise((resolve, reject) => {
        const chunks: Buffer[] = [];

        stream.on("data", (chunk) => chunks.push(chunk));
        stream.on("end", () => resolve(Buffer.concat(chunks)));
        stream.on("error", reject);
    });
}