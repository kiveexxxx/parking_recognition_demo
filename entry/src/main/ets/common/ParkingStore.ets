import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { ParkingRecord } from '../model/ParkingRecord';
import { ParkingFormService } from '../services/ParkingFormService';

const STORE_NAME = 'parking_store';
const KEY_RECORD = 'latest_record';

export class ParkingStore {
  static async read(context: common.Context): Promise<ParkingRecord | undefined> {
    const pref = await preferences.getPreferences(context, STORE_NAME);
    const raw = await pref.get(KEY_RECORD, '');
    if (typeof raw !== 'string' || raw.length === 0) {
      return undefined;
    }
    return JSON.parse(raw) as ParkingRecord;
  }

  static async save(context: common.Context, record: ParkingRecord): Promise<void> {
    const pref = await preferences.getPreferences(context, STORE_NAME);
    await pref.put(KEY_RECORD, JSON.stringify(record));
    await pref.flush();
    await ParkingFormService.updateAll(context, record);
  }

  static async clear(context: common.Context): Promise<void> {
    const pref = await preferences.getPreferences(context, STORE_NAME);
    await pref.delete(KEY_RECORD);
    await pref.flush();
    await ParkingFormService.updateAll(context);
  }
}
