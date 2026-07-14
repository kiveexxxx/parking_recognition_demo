import { Want } from '@kit.AbilityKit';
import { FormExtensionAbility, formBindingData } from '@kit.FormKit';
import { ParkingStore } from '../common/ParkingStore';
import { ParkingFormService } from '../services/ParkingFormService';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = ParkingFormService.extractFormId(want);
    ParkingFormService.addFormId(this.context, formId);
    return ParkingFormService.createBindingData();
  }

  onUpdateForm(formId: string): void {
    this.updateForm(formId);
  }

  onRemoveForm(formId: string): void {
    ParkingFormService.removeFormId(this.context, formId);
  }

  private async updateForm(formId: string): Promise<void> {
    const record = await ParkingStore.read(this.context);
    await ParkingFormService.addFormId(this.context, formId);
    await ParkingFormService.updateAll(this.context, record);
  }
}
