import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { extractParkingNo } from '../common/ParkingNoParser';

export type AiProvider = 'doubao' | 'qwen' | 'custom';

export interface AiConfig {
  provider: AiProvider;
  endpoint: string;
  apiKey: string;
  model: string;
}

export interface RecognitionResult {
  spotNo: string;
  rawText: string;
}

export interface ParkingLocationRecognition {
  hasParkingLocation: boolean;
  spotNo: string;
  areaNo: string;
  confidence: number;
  rawText: string;
}

export interface ParkingSceneRecognition {
  isParkingScene: boolean;
  confidence: number;
  rawText: string;
}

interface ImageUrlPayload {
  url: string;
}

interface AudioPayload {
  data: string;
  format: string;
}

interface AiContentItem {
  type: string;
  text?: string;
  image_url?: ImageUrlPayload;
  input_audio?: AudioPayload;
}

interface ChatMessage {
  role: string;
  content: string | AiContentItem[];
}

interface ChatRequestBody {
  model: string;
  messages: ChatMessage[];
  temperature: number;
}

export class AiParkingRecognizer {
  private config: AiConfig;

  constructor(config: AiConfig) {
    this.config = config;
  }

  async recognizeFromImageUri(imageUri: string): Promise<RecognitionResult> {
    const imageDataUrl = this.readUriAsDataUrl(imageUri, 'image/jpeg');
    const textContent: AiContentItem = {
      type: 'text',
      text: '请从这张停车场照片中提取用户的车位号。只返回车位号，不要解释。'
    };
    const imageContent: AiContentItem = {
      type: 'image_url',
      image_url: {
        url: imageDataUrl
      }
    };
    return this.requestModel([textContent, imageContent]);
  }

  async recognizeParkingLocationFromImageDataUrl(imageDataUrl: string): Promise<ParkingLocationRecognition> {
    const textContent: AiContentItem = {
      type: 'text',
      text: '请判断这张停车场照片中是否同时或部分包含合理的车位号、立柱/区域号。只返回 JSON：{"hasParkingLocation": boolean, "spotNo": string, "areaNo": string, "confidence": number, "rawText": string}。如果没有清晰停车位置，hasParkingLocation=false，confidence 取 0 到 1。'
    };
    const imageContent: AiContentItem = {
      type: 'image_url',
      image_url: {
        url: imageDataUrl
      }
    };
    const result = await this.requestModel([textContent, imageContent]);
    return this.parseParkingLocation(result.rawText);
  }

  async recognizeParkingSceneFromImageDataUrl(imageDataUrl: string): Promise<ParkingSceneRecognition> {
    const textContent: AiContentItem = {
      type: 'text',
      text: '请判断这张小图是否像停车场、地下车库、停车楼或车位场景，是否可见车位线、车辆、立柱、区域标识或车位编号。只返回 JSON：{"isParkingScene": boolean, "confidence": number, "rawText": string}。不要提取车位号。'
    };
    const imageContent: AiContentItem = {
      type: 'image_url',
      image_url: {
        url: imageDataUrl
      }
    };
    const result = await this.requestModel([textContent, imageContent]);
    return this.parseParkingScene(result.rawText);
  }

  async recognizeFromVoiceText(transcript: string): Promise<RecognitionResult> {
    const textContent: AiContentItem = {
      type: 'text',
      text: `请从这段用户语音转写文本中提取车位号。只返回车位号，不要解释。文本：${transcript}`
    };
    return this.requestModel([textContent]);
  }

  async recognizeFromAudioBase64(audioBase64: string, format: string = 'wav'): Promise<RecognitionResult> {
    const textContent: AiContentItem = {
      type: 'text',
      text: '请从这段停车位置语音中提取车位号。只返回车位号，不要解释。'
    };
    const audioContent: AiContentItem = {
      type: 'input_audio',
      input_audio: {
        data: audioBase64,
        format
      }
    };
    return this.requestModel([textContent, audioContent]);
  }

  async recognizeFromAudioFile(path: string, format: string): Promise<RecognitionResult> {
    const audioBase64 = this.readPathAsBase64(path);
    return this.recognizeFromAudioBase64(audioBase64, format);
  }

  private async requestModel(content: AiContentItem[]): Promise<RecognitionResult> {
    if (!this.config.endpoint || !this.config.apiKey) {
      throw new Error('请先配置 AI 接口地址和 API Key');
    }

    const request = http.createHttp();
    try {
      const messages: ChatMessage[] = [
        {
          role: 'system',
          content: '你是停车车位号识别助手。输出必须尽量短，只给车位号。'
        },
        {
          role: 'user',
          content
        }
      ];
      const body: ChatRequestBody = {
        model: this.config.model,
        messages,
        temperature: 0
      };
      const response = await request.request(this.config.endpoint, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${this.config.apiKey}`
        },
        extraData: JSON.stringify(body),
        connectTimeout: 30000,
        readTimeout: 30000
      });
      const raw = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
      const text = this.extractContent(raw);
      return {
        rawText: text,
        spotNo: extractParkingNo(text)
      };
    } finally {
      request.destroy();
    }
  }

  private extractContent(raw: string): string {
    try {
      const body = JSON.parse(raw) as Record<string, object>;
      const choices = body.choices as Array<Record<string, Record<string, string>>>;
      if (choices && choices.length > 0) {
        return choices[0].message.content;
      }
      const output = body.output as Record<string, string>;
      if (output && output.text) {
        return output.text;
      }
    } catch (_) {
      return raw;
    }
    return raw;
  }

  private parseParkingLocation(rawText: string): ParkingLocationRecognition {
    const jsonText = this.extractJsonObject(rawText);
    if (jsonText.length > 0) {
      try {
        const data = JSON.parse(jsonText) as Record<string, Object>;
        const spotNo = this.asString(data.spotNo);
        const areaNo = this.asString(data.areaNo);
        return {
          hasParkingLocation: this.asBoolean(data.hasParkingLocation) && (spotNo.length > 0 || areaNo.length > 0),
          spotNo,
          areaNo,
          confidence: this.asNumber(data.confidence),
          rawText
        };
      } catch (_) {
      }
    }

    const fallbackSpot = extractParkingNo(rawText);
    return {
      hasParkingLocation: fallbackSpot.length > 0,
      spotNo: fallbackSpot,
      areaNo: '',
      confidence: fallbackSpot.length > 0 ? 0.5 : 0,
      rawText
    };
  }

  private parseParkingScene(rawText: string): ParkingSceneRecognition {
    const jsonText = this.extractJsonObject(rawText);
    if (jsonText.length > 0) {
      try {
        const data = JSON.parse(jsonText) as Record<string, Object>;
        return {
          isParkingScene: this.asBoolean(data.isParkingScene),
          confidence: this.asNumber(data.confidence),
          rawText
        };
      } catch (_) {
      }
    }
    const lower = rawText.toLowerCase();
    const likely = rawText.indexOf('停车') >= 0 || rawText.indexOf('车位') >= 0 ||
      rawText.indexOf('车库') >= 0 || lower.indexOf('parking') >= 0;
    return {
      isParkingScene: likely,
      confidence: likely ? 0.5 : 0,
      rawText
    };
  }

  private extractJsonObject(value: string): string {
    const start = value.indexOf('{');
    const end = value.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return value.substring(start, end + 1);
    }
    return '';
  }

  private asString(value: Object | undefined): string {
    return typeof value === 'string' ? value.trim() : '';
  }

  private asBoolean(value: Object | undefined): boolean {
    return typeof value === 'boolean' ? value : false;
  }

  private asNumber(value: Object | undefined): number {
    if (typeof value === 'number') {
      if (value < 0) {
        return 0;
      }
      if (value > 1) {
        return 1;
      }
      return value;
    }
    return 0;
  }

  private readUriAsDataUrl(uri: string, mimeType: string): string {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const stat = fs.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      const helper = new util.Base64Helper();
      const base64 = helper.encodeToStringSync(new Uint8Array(buffer));
      return `data:${mimeType};base64,${base64}`;
    } finally {
      fs.closeSync(file);
    }
  }

  private readPathAsBase64(path: string): string {
    const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      const stat = fs.statSync(file.fd);
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      const helper = new util.Base64Helper();
      return helper.encodeToStringSync(new Uint8Array(buffer));
    } finally {
      fs.closeSync(file);
    }
  }
}
