import { JwtPayload } from "jsonwebtoken";
import { Privileges } from "../../db/models/Plan";
import { Usage, UsageField } from "../../db/models/Usage";
import { User } from "../../db/models/User";

declare global {
    namespace Express {
        interface Request {
            user?: {
                userId: string
                userData: User
                planTitle?: string
                // privileges?: Privileges
                jwtPayload?: JwtPayload
            }
            quotaReservations?: {
                userId: string
                // usages: Map<UsageField, number>
            }[]
        }
    }
}

// ensures this file is treated as a module
export { }; 