import { common, Want } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { wantAgent } from '@kit.AbilityKit';
import { ParkingRecord } from '../model/ParkingRecord';

const LOCATION_NOTIFICATION_ID = 1001;

export class ParkingNotificationService {
  static async requestEnable(context: common.UIAbilityContext): Promise<void> {
    await notificationManager.requestEnableNotification(context);
  }

  static async publishParkingLocation(context: common.Context, record: ParkingRecord): Promise<void> {
    const contentText = ParkingNotificationService.formatRecord(record);
    const want: Want = {
      bundleName: context.applicationInfo.name,
      abilityName: 'EntryAbility',
      parameters: {
        source: 'parking_notification'
      }
    };
    const agent = await wantAgent.getWantAgent({
      wants: [want],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: LOCATION_NOTIFICATION_ID,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
    await notificationManager.publish({
      id: LOCATION_NOTIFICATION_ID,
      notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: '已识别停车位置',
          text: contentText
        }
      },
      wantAgent: agent,
      tapDismissed: true
    });
  }

  static formatRecord(record: ParkingRecord): string {
    const parts: string[] = [];
    if (record.areaNo && record.areaNo.length > 0) {
      parts.push(`区域 ${record.areaNo}`);
    }
    if (record.spotNo && record.spotNo.length > 0) {
      parts.push(`车位 ${record.spotNo}`);
    }
    return parts.length > 0 ? parts.join(' · ') : '停车位置已保存';
  }
}
