// import { Request, Response } from 'express';
// import { getLogger, runWithLogger } from '../observability/requestLoggerContext';
// import TreeNodeRepository from '../db/MongoDB/TreeNodeRepository';
// import LeafRepository from '../db/MongoDB/LeafRepository';
// import { Privileges } from '../db/models/Plan';
// import UsageRepository from '../db/MongoDB/UsageRepository';
// import { Usage } from '../db/models/Usage';
// import { TreeNode } from '../db/models/TreeNode';

// export async function authorizeStorageQuota(req: Request, bytes: number, usage?: Usage, res?: Response, usageRepository?: UsageRepository) {
//     const log = getLogger().child({ step: 'authorizeStorageQuota' });

//     try {
//         log.debug({ reqUser: req.user, bytes })

//         usageRepository ??= new UsageRepository()

//         if (!req.user || !req.user.userData || !req.user.userId) {
//             log.info('Denied: no authenticated user on request');
//             return res?.status(401).json({ status: 'error', error_code: 'UNAUTHENTICATED' }) ?? false;
//         }

//         if (!req.user.privileges) {
//             log.info('Denied: user has no active subscription');
//             return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//         }

//         const maxTotalStorageBytes = req.user!.privileges!.storageBytes;
//         log.debug({ maxTotalStorageBytes }, 'Resolved plan storage limit');

//         const usageUpdateResult = await runWithLogger(log, () => usageRepository!.tryIncrementStorageQuota(req.user!.userId, bytes, maxTotalStorageBytes))
//         log.debug({ usageUpdateResult })
//         if (!usageUpdateResult) {
//             log.info({ bytes }, 'Rejected video upload: exceeds plan storage limit')
//             return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//         }

//         log.info('Storage quota authorized')
//         return true
//     } catch (err) {
//         log.error({ err }, 'caught error in authorizeStorageQuota function')
//         return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//     }
// }

// export async function rollbackStorageQuota(userId: string, bytes: number, usageRepository?: UsageRepository) {
//     const log = getLogger().child({ step: 'authorizeStorageQuota' });

//     try {
//         log.debug({ userId, bytes })

//         usageRepository ??= new UsageRepository()

//         await runWithLogger(log, () => usageRepository!.decrementStorageQuota(userId, bytes))

//         return true
//     } catch (err) {
//         log.error({ err }, 'failed to decrement user usage')
//         return false
//     }
// }

// /**
//  * check if adding a TreeNode is authorized according to categoriesPerNestedLevel privilege
//  * @param req
//  * @param parentId 
//  * @param res if provided, 402 response is sent in case of a failure, false is returned otherwise.
//  * @returns 
//  */
// export async function authorizeCategoriesPerNestedLevel(req: Request, parentId?: string | TreeNode, res?: Response): Promise<boolean | Response<any, Record<string, any>>> {
//     const log = getLogger().child({ step: 'authorizeCategoriesPerNestedLevel' });

//     try {
//         log.debug({ reqUser: req.user })

//         if (!req.user || !req.user.userData || !req.user.userId) {
//             log.info('Denied: no authenticated user on request');
//             return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//         }

//         if (!req.user.privileges) {
//             log.info('Denied: user has no active subscription');
//             return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//         }

//         const tr = new TreeNodeRepository

//         let level: number;

//         if (parentId === undefined || parentId === null) {
//             level = 1
//         } else if (typeof parentId === 'string') {
//             const parentTreeNode = await runWithLogger(log, () => tr.getForUser(parentId, req.user!.userId))
//             if (!parentTreeNode) {
//                 log.info('no parent tree node found')
//                 return res?.status(400).json({ status: 'error', error_code: 'INVALID_PARENT_TREENODE' }) ?? false;
//             }

//             level = parentTreeNode.hierarchyLevel + 1
//         } else
//             level = parentId.hierarchyLevel + 1

//         const categoriesPerNestedLevelCount = await runWithLogger(log, () => tr.countCategoriesPerNestedLevelForUser(req.user!.userId, level))
//         log.debug({ categoriesPerNestedLevelCount })

//         if (typeof categoriesPerNestedLevelCount === 'number' && (categoriesPerNestedLevelCount + 1) >= req.user.privileges.categoriesPerNestedLevel) {
//             log.info('Request is unauthorized')
//             return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//         }

//         log.info('Request is authorized')
//         return true
//     } catch (err) {
//         log.error({ err }, 'caught error in authorizeCategoriesPerNestedLevel function')
//         return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//     }
// }

// /**
//  * check if adding a TreeNode is authorized according to nestedLevels privilege
//  * @param req 
//  * @param parentId if provided, 402 response is sent in case of a failure, false is returned otherwise.
//  * @param res 
//  * @returns 
//  */
// export async function authorizeNestedLevels(req: Request, parentId?: string | TreeNode, res?: Response): Promise<boolean | Response<any, Record<string, any>>> {
//     const log = getLogger().child({ step: 'authorizeNestedLevels' });

//     try {
//         log.debug({ reqUser: req.user })

//         if (!req.user || !req.user.userData || !req.user.userId) {
//             log.info('Denied: no authenticated user on request');
//             return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//         }

//         if (!req.user.privileges) {
//             log.info('Denied: user has no active subscription');
//             return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//         }

//         const tr = new TreeNodeRepository

//         let addingTreeNodeLevel: number;

//         if (parentId === undefined || parentId === null) {
//             addingTreeNodeLevel = 1
//         } else if (typeof parentId === 'string') {
//             const parentTreeNode = await runWithLogger(log, () => tr.getForUser(parentId, req.user!.userId))
//             if (!parentTreeNode) {
//                 log.info('no parent tree node found')
//                 return res?.status(400).json({ status: 'error', error_code: 'INVALID_PARENT_TREENODE' }) ?? false;
//             }

//             addingTreeNodeLevel = parentTreeNode.hierarchyLevel + 1
//         } else
//             addingTreeNodeLevel = parentId.hierarchyLevel + 1

//         let maxHierarchyLevel = await runWithLogger(log, () => tr.countMaxNestedLevelsForUser(req.user!.userId))
//         log.debug({ maxHierarchyLevel })

//         maxHierarchyLevel = Math.max(maxHierarchyLevel ?? 0, addingTreeNodeLevel)

//         if (maxHierarchyLevel >= req.user.privileges.nestedLevels) {
//             log.info('Request is unauthorized')
//             return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//         }

//         log.info('Request is authorized')
//         return true
//     } catch (err) {
//         log.error({ err }, 'caught error in authorizeNestedLevels function')
//         return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//     }
// }

// /**
//  * 
//  * @param req 
//  * @param categoryId 
//  * @param cardsToAdd 
//  * @param res if provided, 402 response is sent in case of a failure, false is returned otherwise.
//  * @returns 
//  */
// export async function authorizeCardsPerCategory(req: Request, categoryId: string, cardsToAdd: number = 1, res: Response): Promise<boolean | Response<any, Record<string, any>>> {
//     const log = getLogger().child({ step: 'authorizeCardsPerCategory' });

//     try {
//         log.debug({ reqUser: req.user })

//         if (!req.user || !req.user.userData || !req.user.userId) {
//             log.info('Denied: no authenticated user on request');
//             return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false
//         }

//         if (!req.user.privileges) {
//             log.info('Denied: user has no active subscription');
//             return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false
//         }

//         const lr = new LeafRepository

//         const cardsPerCategory: number | undefined = await runWithLogger(log, () => lr.countCardsPerCategoryForUser(req.user!.userId, categoryId))
//         log.debug({ cardsPerCategory })

//         if (typeof cardsPerCategory === 'number' && (cardsPerCategory + cardsToAdd) >= req.user.privileges.cardsPerCategory) {
//             log.info('Request is unauthorized')
//             return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//         }

//         log.info('Request is authorized')
//         return true
//     } catch (err) {
//         log.error({ err }, 'caught error in authorizeCardsPerCategory function')
//         return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false
//     }
// }

// /**
//  * 
//  * @param req 
//  * @param leafId 
//  * @param isTerm 
//  * @param contentsToAdd 
//  * @param res if provided, 402 response is sent in case of a failure, false is returned otherwise.
//  * @param contentsPerCardSideCount 
//  * @returns 
//  */
// export async function authorizeContentsPerCardSide(req: Request, leafId: string, isTerm: boolean, contentsToAdd: number = 1, res?: Response, contentsPerCardSideCount?: number): Promise<boolean | Response<any, Record<string, any>>> {
//     const log = getLogger().child({ step: 'authorizeContentsPerCardSide' });

//     try {
//         log.debug({ reqUser: req.user })

//         if (!req.user || !req.user.userData || !req.user.userId) {
//             log.info('Denied: no authenticated user on request');
//             return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//         }

//         if (!req.user.privileges) {
//             log.info('Denied: user has no active subscription');
//             return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//         }

//         const lr = new LeafRepository

//         contentsPerCardSideCount = contentsPerCardSideCount ?? await runWithLogger(log, () => lr.countContentsPerCardSideForUser(req.user!.userId, leafId, isTerm))
//         log.debug({ contentsPerCardSideCount })

//         if (typeof contentsPerCardSideCount === 'number' && (contentsPerCardSideCount + contentsToAdd) >= req.user.privileges.contentsPerCardSide) {
//             log.info('Request is unauthorized')
//             return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//         }

//         log.info('Request is authorized')
//         return true
//     } catch (err) {
//         log.error({ err }, 'caught error in authorizeContentsPerCardSide function')
//         return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//     }
// }

// /**
//  * 
//  * @param req 
//  * @param leafId 
//  * @param isTerm 
//  * @param content 
//  * @param valuePerContentCount 
//  * @param res if provided, 402 response is sent in case of a failure, false is returned otherwise.
//  * @param valuesToAdd 
//  * @returns 
//  */
// export async function authorizeValuePerContent(req: Request, leafId: string, isTerm: boolean, content: keyof Privileges['valuePerContent'], valuePerContentCount: number, res?: Response, valuesToAdd: number = 1): Promise<boolean | Response<any, Record<string, any>>> {
//     const log = getLogger().child({ step: 'authorizeValuePerContent' });

//     try {

//         log.debug({ reqUser: req.user, leafId, isTerm, content, valuePerContentCount, valuesToAdd })

//         if (!req.user || !req.user.userData || !req.user.userId) {
//             log.info('Denied: no authenticated user on request');
//             return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//         }

//         if (!req.user.privileges) {
//             log.info('Denied: user has no active subscription');
//             return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//         }

//         if ((valuePerContentCount + valuesToAdd) >= req.user.privileges.valuePerContent[content]) {
//             log.info('Request is unauthorized')
//             return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//         }

//         log.info('Request is authorized')
//         return true
//     } catch (err) {
//         log.error({ err }, 'caught error in authorizeValuePerContent function')
//         return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//     }
// }

// /**
//  * 
//  * @param req 
//  * @param contentType 
//  * @param res if provided, 402 response is sent in case of a failure, false is returned otherwise.
//  * @returns 
//  */
// export function authorizeAllowedContentTypes(req: Request, contentType: keyof Privileges['allowedContentTypes'], res?: Response): boolean | Response<any, Record<string, any>> {
//     const log = getLogger().child({ step: 'authorizeAllowedContentTypes' });

//     try {
//         log.debug({ reqUser: req.user, contentType })

//         if (!req.user || !req.user.userData || !req.user.userId) {
//             log.info('Denied: no authenticated user on request');
//             return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//         }

//         if (!req.user.privileges) {
//             log.info('Denied: user has no active subscription');
//             return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//         }

//         if (!req.user.privileges.allowedContentTypes[contentType]) {
//             log.info('Request is unauthorized')
//             return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//         }

//         log.info('Request is authorized')
//         return true
//     } catch (err) {
//         log.error({ err }, 'caught error in authorizeAllowedContentTypes function')
//         return res?.status(402).json({ status: 'error', error_code: 'QUOTA_EXCEEDED' }) ?? false;
//     }
// }
