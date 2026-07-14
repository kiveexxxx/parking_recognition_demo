import { common, Permissions } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates, preferences } from '@kit.ArkData';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent } from '@kit.AbilityKit';
import { ImagePreprocessor } from './ImagePreprocessor';
import { AiParkingRecognizer, ParkingLocationRecognition } from './AiParkingRecognizer';
import { ParkingStore } from '../common/ParkingStore';
import { ParkingRecord } from '../model/ParkingRecord';
import { ParkingNotificationService } from './ParkingNotificationService';

const MONITOR_STORE = 'parking_photo_monitor';
const KEY_ENABLED = 'enabled';
const KEY_STARTED_AT = 'started_at';

export interface MonitorStatus {
  enabled: boolean;
  running: boolean;
  startedAt: number;
  message: string;
}

export class CameraPhotoMonitor {
  private context: common.UIAbilityContext;
  private recognizer: AiParkingRecognizer;
  private helper: photoAccessHelper.PhotoAccessHelper;
  private callback?: (changes: photoAccessHelper.PhotoAssetChangeInfos) => void;
  private processedUris: Set<string> = new Set();
  private pendingUris: string[] = [];
  private startedAt: number = 0;
  private running: boolean = false;
  private processing: boolean = false;

  constructor(context: common.UIAbilityContext, recognizer: AiParkingRecognizer) {
    this.context = context;
    this.recognizer = recognizer;
    this.helper = photoAccessHelper.getPhotoAccessHelper(context);
  }

  async restoreIfEnabled(): Promise<MonitorStatus> {
    const pref = await preferences.getPreferences(this.context, MONITOR_STORE);
    const enabled = await pref.get(KEY_ENABLED, false) as boolean;
    if (!enabled) {
      return this.status('监听未开启');
    }
    this.startedAt = await pref.get(KEY_STARTED_AT, Date.now()) as number;
    await this.startInternal(false);
    return this.status('已恢复停车照片监听');
  }

  async start(): Promise<MonitorStatus> {
    this.startedAt = Date.now();
    await this.saveEnabled(true);
    await this.startInternal(true);
    return this.status('正在监听系统相机照片');
  }

  async stop(): Promise<MonitorStatus> {
    if (this.callback) {
      this.helper.off('photoChange', this.callback);
      this.callback = undefined;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(this.context);
    } catch (_) {
    }
    this.running = false;
    await this.saveEnabled(false);
    return this.status('监听已关闭');
  }

  status(message: string = ''): MonitorStatus {
    return {
      enabled: this.running,
      running: this.running,
      startedAt: this.startedAt,
      message
    };
  }

  private async startInternal(startBackground: boolean): Promise<void> {
    if (!this.callback) {
      this.callback = (changes: photoAccessHelper.PhotoAssetChangeInfos) => {
        this.handleChanges(changes);
      };
      this.helper.on('photoChange', this.callback);
    }
    this.running = true;
    if (startBackground) {
      await this.startBackgroundTask();
    }
  }

  private async startBackgroundTask(): Promise<void> {
    const want = await wantAgent.getWantAgent({
      wants: [
        {
          bundleName: this.context.applicationInfo.name,
          abilityName: 'EntryAbility'
        }
      ],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 2001,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
    await backgroundTaskManager.startBackgroundRunning(
      this.context,
      backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
      want
    );
  }

  private handleChanges(changes: photoAccessHelper.PhotoAssetChangeInfos): void {
    if (!changes.assetChangeDatas) {
      return;
    }
    changes.assetChangeDatas.forEach((item: photoAccessHelper.PhotoAssetChangeData) => {
      if (!item.isDeleted && item.assetBeforeChange === null && item.assetAfterChange !== null) {
        const changed = item.assetAfterChange;
        if (changed && changed.uri.length > 0 && !this.processedUris.has(changed.uri) && this.pendingUris.indexOf(changed.uri) < 0) {
          this.pendingUris.push(changed.uri);
        }
      }
    });
    this.processQueue();
  }

  private async processQueue(): Promise<void> {
    if (this.processing) {
      return;
    }
    const uri = this.pendingUris.shift();
    if (!uri) {
      return;
    }
    await this.processNext(uri);
    await this.processQueue();
  }

  private async processNext(uri: string): Promise<void> {
    this.processing = true;
    this.processedUris.add(uri);
    const delayInfo = backgroundTaskManager.requestSuspendDelay('识别停车照片', () => {});
    try {
      const asset = await this.fetchAsset(uri);
      if (!asset || !this.isCameraAsset(asset) || !this.isAfterStart(asset)) {
        return;
      }
      const sceneThumbnail = await asset.getThumbnail({
        width: 192,
        height: 192
      });
      const sceneImage = await ImagePreprocessor.compressForSceneCheck(sceneThumbnail);
      sceneThumbnail.release();
      const scene = await this.recognizer.recognizeParkingSceneFromImageDataUrl(sceneImage.dataUrl);
      if (!scene.isParkingScene || scene.confidence < 0.35) {
        return;
      }

      const thumbnail = await asset.getThumbnail({
        width: 512,
        height: 512
      });
      const compressed = await ImagePreprocessor.compressForParkingRecognition(thumbnail);
      thumbnail.release();
      const result = await this.recognizer.recognizeParkingLocationFromImageDataUrl(compressed.dataUrl);
      if (!this.shouldSave(result)) {
        return;
      }
      const record: ParkingRecord = {
        spotNo: result.spotNo,
        areaNo: result.areaNo,
        confidence: result.confidence,
        rawText: result.rawText,
        source: 'camera_monitor',
        updatedAt: Date.now()
      };
      await ParkingStore.save(this.context, record);
      await ParkingNotificationService.publishParkingLocation(this.context, record);
    } finally {
      backgroundTaskManager.cancelSuspendDelay(delayInfo.requestId);
      this.processing = false;
    }
  }

  private async fetchAsset(uri: string): Promise<photoAccessHelper.PhotoAsset | undefined> {
    const predicates = new dataSharePredicates.DataSharePredicates();
    predicates.equalTo(photoAccessHelper.PhotoKeys.URI, uri);
    predicates.limit(1, 0);
    const result = await this.helper.getAssets({
      fetchColumns: [
        photoAccessHelper.PhotoKeys.URI,
        photoAccessHelper.PhotoKeys.DISPLAY_NAME,
        photoAccessHelper.PhotoKeys.PHOTO_TYPE,
        photoAccessHelper.PhotoKeys.DATE_ADDED_MS,
        photoAccessHelper.PhotoKeys.DATE_TAKEN_MS
      ],
      predicates
    });
    try {
      return await result.getFirstObject();
    } finally {
      result.close();
    }
  }

  private isCameraAsset(asset: photoAccessHelper.PhotoAsset): boolean {
    const uri = asset.uri;
    if (uri.length === 0) {
      return false;
    }
    const name = asset.displayName ? asset.displayName.toLowerCase() : '';
    return name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png') || uri.indexOf('Photo') >= 0;
  }

  private isAfterStart(asset: photoAccessHelper.PhotoAsset): boolean {
    const dateTaken = this.memberToNumber(asset.get(photoAccessHelper.PhotoKeys.DATE_TAKEN_MS));
    const dateAdded = this.memberToNumber(asset.get(photoAccessHelper.PhotoKeys.DATE_ADDED_MS));
    const capturedAt = dateTaken > 0 ? dateTaken : dateAdded;
    return capturedAt === 0 || capturedAt >= this.startedAt;
  }

  private memberToNumber(value: photoAccessHelper.MemberType): number {
    if (typeof value === 'number') {
      return value;
    }
    if (typeof value === 'string') {
      const parsed = Number(value);
      return Number.isNaN(parsed) ? 0 : parsed;
    }
    return 0;
  }

  private shouldSave(result: ParkingLocationRecognition): boolean {
    return result.hasParkingLocation && (result.spotNo.length > 0 || result.areaNo.length > 0) && result.confidence >= 0.4;
  }

  private async saveEnabled(enabled: boolean): Promise<void> {
    const pref = await preferences.getPreferences(this.context, MONITOR_STORE);
    await pref.put(KEY_ENABLED, enabled);
    await pref.put(KEY_STARTED_AT, this.startedAt);
    await pref.flush();
  }
}

export const PHOTO_MONITOR_PERMISSIONS: Permissions[] = [
  'ohos.permission.READ_IMAGEVIDEO',
  'ohos.permission.KEEP_BACKGROUND_RUNNING'
] as Permissions[];
