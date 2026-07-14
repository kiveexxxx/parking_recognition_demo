import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';

export async function requestPermissions(context: common.Context, permissions: Permissions[]): Promise<boolean> {
  const atManager = abilityAccessCtrl.createAtManager();
  const result = await atManager.requestPermissionsFromUser(context, permissions);
  return result.authResults.every((item: number) => item === 0);
}
