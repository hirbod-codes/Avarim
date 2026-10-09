import { ObjectId } from "mongodb";
import { addMethod, AnyObject, Flags, InferType, Maybe, mixed, number, object, string } from "yup";

declare module 'yup' {
    interface ObjectSchema<
        TIn extends Maybe<AnyObject>,
        TContext = AnyObject,
        TDefault = any,
        TFlags extends Flags = ''
    > {
        stripUndefined(): this;
        stripNull(): this;
    }

    interface StringSchema {
        objectIdString(): this;
        nonUndefined(): this;
    }
}

export const addYupMethods = () => {
    addMethod(object as any, 'stripUndefined', function (obj) {
        return this.transform((obj: any) => {
            if (!obj || typeof obj !== 'object')
                return obj

            return Object.fromEntries(
                Object.entries(obj).filter(f => f[1] !== undefined)
            )
        })
    })

    addMethod(object as any, 'stripNull', function (obj) {
        return this.transform((obj: any) => {
            if (!obj || typeof obj !== 'object')
                return obj

            return Object.fromEntries(
                Object.entries(obj).filter(f => f[1] !== null)
            )
        })
    })

    addMethod(string as any, 'objectIdString', function (message = 'Invalid id provided') {
        return this.test('object-id', message, (v: any) => v === null || v === undefined || ObjectId.isValid(v)).label('Id')
    })

    addMethod(string as any, 'nonUndefined', function (message = 'Undefined string provided') {
        return this.test('string', message, (v: any) => v !== undefined)
    })
}

export const likeObjectId = mixed((v): v is (ObjectId | string) => v instanceof ObjectId || ObjectId.isValid(v))

export const stringObjectId = mixed((v): v is string => {
    try { ObjectId.createFromHexString(v) }
    catch (e) { return false }
    return typeof v === 'string' && ObjectId.isValid(v);
})

export const localizedText = mixed<{ [key: string]: string }>().optional().test((v: any) => {
    if (v === undefined || v === null)
        return true

    if (typeof v !== 'object' || Array.isArray(v))
        return false

    for (const k in v)
        if (Object.prototype.hasOwnProperty.call(v, k))
            if (!string().required().strict(true).isValidSync(v[k]))
                return false

    return true
}).transform((v, ov) => {
    return ov
})

export function uniqueArrayTest(list: any) {
    if (!list) return true
    if (!Array.isArray(list)) return false
    return list.length === new Set(list).size;
}

export const contentTypeSchema = object().shape({
    mimeType: string().required(),
    extension: string().required(),
})
export type ContentType = InferType<typeof contentTypeSchema>
