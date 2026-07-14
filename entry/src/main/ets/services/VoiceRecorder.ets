import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';

export interface VoiceRecording {
  path: string;
  format: string;
  durationMs: number;
}

export class VoiceRecorder {
  private context: common.Context;
  private recorder?: media.AVRecorder;
  private file?: fs.File;
  private outputPath: string = '';
  private startedAt: number = 0;

  constructor(context: common.Context) {
    this.context = context;
  }

  isRecording(): boolean {
    return this.recorder !== undefined;
  }

  async start(): Promise<void> {
    if (this.recorder) {
      return;
    }

    this.outputPath = `${this.context.cacheDir}/parking_voice_${Date.now()}.m4a`;
    this.file = fs.openSync(this.outputPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);

    const profile: media.AVRecorderProfile = {
      audioBitrate: 64000,
      audioChannels: 1,
      audioCodec: media.CodecMimeType.AUDIO_AAC,
      audioSampleRate: 16000,
      fileFormat: media.ContainerFormatType.CFT_MPEG_4A
    };
    const config: media.AVRecorderConfig = {
      audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_VOICE_RECOGNITION,
      profile,
      url: `fd://${this.file.fd}`
    };

    this.recorder = await media.createAVRecorder();
    await this.recorder.prepare(config);
    await this.recorder.start();
    this.startedAt = Date.now();
  }

  async stop(): Promise<VoiceRecording> {
    if (!this.recorder || !this.file) {
      throw new Error('当前没有正在录制的语音');
    }

    const recorder = this.recorder;
    const file = this.file;
    const path = this.outputPath;
    const durationMs = Date.now() - this.startedAt;

    this.recorder = undefined;
    this.file = undefined;
    this.outputPath = '';
    this.startedAt = 0;

    try {
      await recorder.stop();
      await recorder.release();
    } finally {
      fs.closeSync(file);
    }

    return {
      path,
      format: 'm4a',
      durationMs
    };
  }

  async cancel(): Promise<void> {
    if (!this.recorder || !this.file) {
      return;
    }

    const recorder = this.recorder;
    const file = this.file;
    this.recorder = undefined;
    this.file = undefined;
    this.outputPath = '';
    this.startedAt = 0;

    try {
      await recorder.stop();
      await recorder.release();
    } finally {
      fs.closeSync(file);
    }
  }
}
