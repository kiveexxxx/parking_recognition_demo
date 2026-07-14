import { common, Want } from '@kit.AbilityKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { preferences } from '@kit.ArkData';
import { ParkingRecord } from '../model/ParkingRecord';

const FORM_STORE = 'parking_form_store';
const KEY_FORM_IDS = 'form_ids';

interface ParkingFormData {
  spotNo: string;
  areaNo: string;
  sourceText: string;
  updatedAtText: string;
  emptyText: string;
}

export class ParkingFormService {
  static createBindingData(record?: ParkingRecord): formBindingData.FormBindingData {
    const data = ParkingFormService.toFormData(record);
    return formBindingData.createFormBindingData(data);
  }

  static async addFormId(context: common.Context, formId: string): Promise<void> {
    if (formId.length === 0) {
      return;
    }
    const ids = await ParkingFormService.readFormIds(context);
    if (ids.indexOf(formId) < 0) {
      ids.push(formId);
      await ParkingFormService.writeFormIds(context, ids);
    }
  }

  static async removeFormId(context: common.Context, formId: string): Promise<void> {
    const ids = await ParkingFormService.readFormIds(context);
    const next = ids.filter((id: string) => id !== formId);
    await ParkingFormService.writeFormIds(context, next);
  }

  static async updateAll(context: common.Context, record?: ParkingRecord): Promise<void> {
    const ids = await ParkingFormService.readFormIds(context);
    const data = ParkingFormService.createBindingData(record);
    for (let index = 0; index < ids.length; index++) {
      try {
        await formProvider.updateForm(ids[index], data);
      } catch (_) {
      }
    }
  }

  static extractFormId(want: Want): string {
    const params = want.parameters;
    if (!params) {
      return '';
    }
    return ParkingFormService.asString(params['ohos.extra.param.key.form_identity']) ||
      ParkingFormService.asString(params['formId']) ||
      ParkingFormService.asString(params['form_id']);
  }

  private static toFormData(record?: ParkingRecord): ParkingFormData {
    if (!record) {
      return {
        spotNo: '',
        areaNo: '',
        sourceText: '暂无记录',
        updatedAtText: '',
        emptyText: '暂无停车位置'
      };
    }
    return {
      spotNo: record.spotNo,
      areaNo: record.areaNo ? record.areaNo : '',
      sourceText: ParkingFormService.sourceText(record.source),
      updatedAtText: new Date(record.updatedAt).toLocaleString(),
      emptyText: ''
    };
  }

  private static sourceText(source: string): string {
    if (source === 'camera_monitor') {
      return '系统相机识别';
    }
    if (source === 'photo') {
      return '拍照识别';
    }
    if (source === 'voice') {
      return '语音输入';
    }
    return '键盘输入';
  }

  private static async readFormIds(context: common.Context): Promise<string[]> {
    const pref = await preferences.getPreferences(context, FORM_STORE);
    const raw = await pref.get(KEY_FORM_IDS, '[]');
    if (typeof raw !== 'string') {
      return [];
    }
    try {
      return JSON.parse(raw) as string[];
    } catch (_) {
      return [];
    }
  }

  private static async writeFormIds(context: common.Context, ids: string[]): Promise<void> {
    const pref = await preferences.getPreferences(context, FORM_STORE);
    await pref.put(KEY_FORM_IDS, JSON.stringify(ids));
    await pref.flush();
  }

  private static asString(value: Object | undefined): string {
    return typeof value === 'string' ? value : '';
  }
}
