import { common, Permissions } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { ParkingStore } from '../common/ParkingStore';
import { requestPermissions } from '../common/PermissionHelper';
import { extractParkingNo } from '../common/ParkingNoParser';
import { ParkingRecord } from '../model/ParkingRecord';
import { AiParkingRecognizer } from '../services/AiParkingRecognizer';
import { DEFAULT_AI_CONFIG } from '../services/RecognizerConfig';
import { VoiceRecorder, VoiceRecording } from '../services/VoiceRecorder';
import { CameraPhotoMonitor, PHOTO_MONITOR_PERMISSIONS, MonitorStatus } from '../services/CameraPhotoMonitor';
import { ParkingNotificationService } from '../services/ParkingNotificationService';

type InputMode = 'manual' | 'photo' | 'voice';

@Entry
@Component
struct Index {
  @State private spotNo: string = '';
  @State private manualText: string = '';
  @State private voiceText: string = '';
  @State private recording: boolean = false;
  @State private recordingSeconds: number = 0;
  @State private lastVoiceInfo: string = '';
  @State private lastSource: string = '未记录';
  @State private updatedAtText: string = '';
  @State private busy: boolean = false;
  @State private selectedMode: InputMode = 'manual';
  @State private monitorEnabled: boolean = false;
  @State private monitorMessage: string = '停车照片监听未开启';

  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private recognizer: AiParkingRecognizer = new AiParkingRecognizer(DEFAULT_AI_CONFIG);
  private voiceRecorder: VoiceRecorder = new VoiceRecorder(this.context);
  private photoMonitor: CameraPhotoMonitor = new CameraPhotoMonitor(this.context, this.recognizer);
  private recordingTimer: number = 0;

  async aboutToAppear(): Promise<void> {
    const record = await ParkingStore.read(this.context);
    if (record) {
      this.applyRecord(record);
    }
    const status = await this.photoMonitor.restoreIfEnabled();
    this.applyMonitorStatus(status);
  }

  build() {
    Column() {
      Row() {
        Column() {
          Text('车位记录')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor('#102A43');
          Text('保存当前停车位置，离开时更容易找回车辆')
            .fontSize(14)
            .fontColor('#52616B')
            .margin({ top: 6 });
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1);
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 22, bottom: 18 });

      Column() {
        Text(this.spotNo.length > 0 ? this.spotNo : '暂无车位号')
          .fontSize(this.spotNo.length > 0 ? 42 : 30)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.spotNo.length > 0 ? '#0F4C5C' : '#8294A5')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(`${this.lastSource}${this.updatedAtText.length > 0 ? ' · ' + this.updatedAtText : ''}`)
          .fontSize(13)
          .fontColor('#66788A')
          .margin({ top: 8 });
      }
      .width('90%')
      .padding(22)
      .borderRadius(8)
      .backgroundColor('#E8F6F3')
      .alignItems(HorizontalAlign.Start);

      Row() {
        this.ModeButton('键盘', 'manual');
        this.ModeButton('拍照', 'photo');
        this.ModeButton('语音', 'voice');
      }
      .width('90%')
      .height(48)
      .padding(4)
      .margin({ top: 18 })
      .borderRadius(8)
      .backgroundColor('#EEF2F6');

      Column() {
        Row() {
          Column() {
            Text('系统相机监听')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#243B53');
            Text(this.monitorMessage)
              .fontSize(12)
              .fontColor('#66788A')
              .margin({ top: 4 });
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start);
          Toggle({ type: ToggleType.Switch, isOn: this.monitorEnabled })
            .enabled(!this.busy)
            .onChange((isOn: boolean) => {
              this.togglePhotoMonitor(isOn);
            });
        }
        .width('100%');
      }
      .width('90%')
      .padding(14)
      .margin({ top: 14 })
      .borderRadius(8)
      .backgroundColor('#FFFFFF');

      Column() {
        if (this.selectedMode === 'manual') {
          this.ManualPanel();
        } else if (this.selectedMode === 'photo') {
          this.PhotoPanel();
        } else {
          this.VoicePanel();
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 20, right: 20, top: 20 });

      Button('清除记录')
        .width('90%')
        .height(44)
        .fontSize(15)
        .fontColor('#A23E48')
        .backgroundColor('#FDECEF')
        .borderRadius(8)
        .margin({ bottom: 20 })
        .enabled(!this.busy)
        .onClick(async () => {
          await ParkingStore.clear(this.context);
          this.spotNo = '';
          this.lastSource = '未记录';
          this.updatedAtText = '';
          promptAction.showToast({ message: '已清除' });
        });
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F7FAFC');
  }

  @Builder
  private ModeButton(label: string, mode: InputMode) {
    Button(label)
      .layoutWeight(1)
      .height(40)
      .fontSize(15)
      .fontColor(this.selectedMode === mode ? '#FFFFFF' : '#334E68')
      .backgroundColor(this.selectedMode === mode ? '#176B87' : Color.Transparent)
      .borderRadius(6)
      .enabled(!this.busy)
      .onClick(() => {
        this.selectedMode = mode;
      });
  }

  @Builder
  private ManualPanel() {
    Column() {
      Text('输入车位号')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#243B53');
      TextInput({ placeholder: '例如 B2-138、A区052、负一层C18', text: this.manualText })
        .height(52)
        .fontSize(17)
        .margin({ top: 14 })
        .onChange((value: string) => {
          this.manualText = value;
        });
      Button('保存')
        .width('100%')
        .height(48)
        .margin({ top: 16 })
        .borderRadius(8)
        .backgroundColor('#176B87')
        .enabled(!this.busy)
        .onClick(async () => {
          const value = extractParkingNo(this.manualText);
          if (!value) {
            promptAction.showToast({ message: '请输入车位号' });
            return;
          }
          await this.saveRecord(value, 'manual');
        });
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%');
  }

  @Builder
  private PhotoPanel() {
    Column() {
      Text('拍照识别')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#243B53');
      Text('选择或拍摄包含车位标识的照片，应用会把图片交给配置的多模态模型提取车位号。')
        .fontSize(14)
        .fontColor('#52616B')
        .lineHeight(21)
        .margin({ top: 10 });
      Button(this.busy ? '识别中...' : '选择照片识别')
        .width('100%')
        .height(48)
        .margin({ top: 16 })
        .borderRadius(8)
        .backgroundColor('#176B87')
        .enabled(!this.busy)
        .onClick(() => this.pickAndRecognizePhoto());
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%');
  }

  @Builder
  private VoicePanel() {
    Column() {
      Text('语音识别')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#243B53');
      Text(this.recording ? `正在录音 ${this.recordingSeconds}s` : '说出车位号，停止录音后会调用配置的语音/多模态模型提取车位号。')
        .fontSize(14)
        .fontColor('#52616B')
        .lineHeight(21)
        .margin({ top: 10 });
      if (this.lastVoiceInfo.length > 0) {
        Text(this.lastVoiceInfo)
          .fontSize(13)
          .fontColor('#66788A')
          .margin({ top: 8 });
      }
      Button(this.voiceButtonText())
        .width('100%')
        .height(52)
        .margin({ top: 16 })
        .borderRadius(8)
        .fontSize(17)
        .backgroundColor(this.recording ? '#A23E48' : '#176B87')
        .enabled(!this.busy)
        .onClick(() => this.toggleVoiceRecording());
      TextInput({ placeholder: '也可以输入语音转写文本调试，例如“我的车停在负一层 C18”', text: this.voiceText })
        .height(52)
        .fontSize(16)
        .margin({ top: 18 })
        .onChange((value: string) => {
          this.voiceText = value;
        });
      Button(this.busy ? '提取中...' : '从转写文本提取')
        .width('100%')
        .height(44)
        .margin({ top: 12 })
        .borderRadius(8)
        .backgroundColor('#E8F6F3')
        .fontColor('#0F4C5C')
        .enabled(!this.busy && !this.recording)
        .onClick(() => this.recognizeVoiceText());
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%');
  }

  private async pickAndRecognizePhoto(): Promise<void> {
    const ok = await requestPermissions(this.context, ['ohos.permission.CAMERA'] as Permissions[]);
    if (!ok) {
      promptAction.showToast({ message: '需要相机权限' });
      return;
    }

    try {
      this.busy = true;
      const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      photoSelectOptions.maxSelectNumber = 1;
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const result = await photoPicker.select(photoSelectOptions);
      if (!result.photoUris || result.photoUris.length === 0) {
        return;
      }
      const recognition = await this.recognizer.recognizeFromImageUri(result.photoUris[0]);
      await this.saveRecord(recognition.spotNo, 'photo');
    } catch (error) {
      promptAction.showToast({ message: `照片识别未完成：${JSON.stringify(error)}` });
    } finally {
      this.busy = false;
    }
  }

  private async recognizeVoiceText(): Promise<void> {
    if (!this.voiceText) {
      promptAction.showToast({ message: '请先输入或接入语音转写文本' });
      return;
    }
    try {
      this.busy = true;
      const ok = await requestPermissions(this.context, ['ohos.permission.MICROPHONE'] as Permissions[]);
      if (!ok) {
        promptAction.showToast({ message: '需要麦克风权限' });
        return;
      }
      const recognition = await this.recognizer.recognizeFromVoiceText(this.voiceText);
      await this.saveRecord(recognition.spotNo, 'voice');
    } catch (error) {
      const fallback = extractParkingNo(this.voiceText);
      if (fallback) {
        await this.saveRecord(fallback, 'voice');
      } else {
        promptAction.showToast({ message: `语音识别未完成：${JSON.stringify(error)}` });
      }
    } finally {
      this.busy = false;
    }
  }

  private async toggleVoiceRecording(): Promise<void> {
    if (this.recording) {
      await this.stopVoiceRecordingAndRecognize();
    } else {
      await this.startVoiceRecording();
    }
  }

  private async startVoiceRecording(): Promise<void> {
    const ok = await requestPermissions(this.context, ['ohos.permission.MICROPHONE'] as Permissions[]);
    if (!ok) {
      promptAction.showToast({ message: '需要麦克风权限' });
      return;
    }

    try {
      this.busy = true;
      await this.voiceRecorder.start();
      this.recording = true;
      this.recordingSeconds = 0;
      this.lastVoiceInfo = '请说出车位号，例如“我的车停在负一层 C18”。';
      this.startRecordingTimer();
    } catch (error) {
      promptAction.showToast({ message: `录音启动失败：${JSON.stringify(error)}` });
    } finally {
      this.busy = false;
    }
  }

  private async stopVoiceRecordingAndRecognize(): Promise<void> {
    try {
      this.busy = true;
      this.stopRecordingTimer();
      const recording = await this.voiceRecorder.stop();
      this.recording = false;
      this.lastVoiceInfo = `录音 ${Math.max(1, Math.round(recording.durationMs / 1000))}s，正在识别...`;
      await this.recognizeVoiceRecording(recording);
    } catch (error) {
      this.recording = false;
      promptAction.showToast({ message: `语音识别未完成：${JSON.stringify(error)}` });
    } finally {
      this.busy = false;
    }
  }

  private async recognizeVoiceRecording(recording: VoiceRecording): Promise<void> {
    const recognition = await this.recognizer.recognizeFromAudioFile(recording.path, recording.format);
    this.voiceText = recognition.rawText;
    this.lastVoiceInfo = `识别结果：${recognition.spotNo}`;
    await this.saveRecord(recognition.spotNo, 'voice');
  }

  private startRecordingTimer(): void {
    this.stopRecordingTimer();
    this.recordingTimer = setInterval(() => {
      this.recordingSeconds += 1;
    }, 1000);
  }

  private stopRecordingTimer(): void {
    if (this.recordingTimer !== 0) {
      clearInterval(this.recordingTimer);
      this.recordingTimer = 0;
    }
  }

  private voiceButtonText(): string {
    if (this.busy && !this.recording) {
      return '处理中...';
    }
    if (this.recording) {
      return this.busy ? '停止中...' : '停止录音并识别';
    }
    return '开始录音';
  }

  private async saveRecord(spotNo: string, source: InputMode): Promise<void> {
    const record: ParkingRecord = {
      spotNo,
      source,
      updatedAt: Date.now()
    };
    await ParkingStore.save(this.context, record);
    this.applyRecord(record);
    promptAction.showToast({ message: '车位号已保存' });
  }

  private applyRecord(record: ParkingRecord): void {
    const parts: string[] = [];
    if (record.areaNo && record.areaNo.length > 0) {
      parts.push(`区域 ${record.areaNo}`);
    }
    if (record.spotNo.length > 0) {
      parts.push(record.spotNo);
    }
    this.spotNo = parts.length > 0 ? parts.join(' · ') : record.spotNo;
    this.lastSource = this.sourceLabel(record.source);
    this.updatedAtText = new Date(record.updatedAt).toLocaleString();
  }

  private sourceLabel(source: InputMode | 'camera_monitor'): string {
    if (source === 'manual') {
      return '键盘输入';
    }
    if (source === 'photo') {
      return '拍照识别';
    }
    if (source === 'camera_monitor') {
      return '系统相机识别';
    }
    return '语音输入';
  }

  private async togglePhotoMonitor(isOn: boolean): Promise<void> {
    try {
      this.busy = true;
      if (isOn) {
        const ok = await requestPermissions(this.context, PHOTO_MONITOR_PERMISSIONS);
        if (!ok) {
          this.applyMonitorStatus(this.photoMonitor.status('需要相册读取和后台运行权限'));
          return;
        }
        await ParkingNotificationService.requestEnable(this.context);
        const status = await this.photoMonitor.start();
        this.applyMonitorStatus(status);
      } else {
        const status = await this.photoMonitor.stop();
        this.applyMonitorStatus(status);
      }
    } catch (error) {
      this.monitorEnabled = false;
      this.monitorMessage = `监听状态更新失败：${JSON.stringify(error)}`;
      promptAction.showToast({ message: this.monitorMessage });
    } finally {
      this.busy = false;
    }
  }

  private applyMonitorStatus(status: MonitorStatus): void {
    this.monitorEnabled = status.running;
    this.monitorMessage = status.message;
  }
}
