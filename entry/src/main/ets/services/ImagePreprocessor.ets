import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';

export interface CompressedImage {
  dataUrl: string;
  bytes: number;
  width: number;
  height: number;
}

interface CompressionProfile {
  maxLongSide: number;
  quality: number;
  minLongSide?: number;
}

export class ImagePreprocessor {
  static async compressForSceneCheck(pixelMap: image.PixelMap): Promise<CompressedImage> {
    return ImagePreprocessor.packWithProfile(pixelMap, {
      maxLongSide: 192,
      quality: 55,
      minLongSide: 192
    });
  }

  static async compressForParkingRecognition(pixelMap: image.PixelMap): Promise<CompressedImage> {
    return ImagePreprocessor.packWithProfile(pixelMap, {
      maxLongSide: 512,
      quality: 72,
      minLongSide: 512
    });
  }

  static async compressPixelMap(pixelMap: image.PixelMap): Promise<CompressedImage> {
    const first = await ImagePreprocessor.packWithProfile(pixelMap, {
      maxLongSide: 1280,
      quality: 75
    });
    if (first.bytes <= 800 * 1024) {
      return first;
    }
    return ImagePreprocessor.packWithProfile(pixelMap, {
      maxLongSide: 960,
      quality: 65
    });
  }

  private static async packWithProfile(pixelMap: image.PixelMap, profile: CompressionProfile): Promise<CompressedImage> {
    const info = await pixelMap.getImageInfo();
    const width = info.size.width;
    const height = info.size.height;
    const longSide = Math.max(width, height);
    const minLongSide = profile.minLongSide ? profile.minLongSide : 720;
    const targetLongSide = Math.max(minLongSide, Math.min(profile.maxLongSide, longSide));
    const scale = longSide > targetLongSide ? targetLongSide / longSide : 1;
    const targetWidth = Math.max(1, Math.round(width * scale));
    const targetHeight = Math.max(1, Math.round(height * scale));
    let targetMap = pixelMap;

    if (scale < 1) {
      targetMap = await pixelMap.createScaledPixelMap(scale, scale);
    }

    try {
      const packer = image.createImagePacker();
      const data = await packer.packToData(targetMap, {
        format: 'image/jpeg',
        quality: profile.quality
      });
      const helper = new util.Base64Helper();
      const base64 = helper.encodeToStringSync(new Uint8Array(data));
      return {
        dataUrl: `data:image/jpeg;base64,${base64}`,
        bytes: data.byteLength,
        width: targetWidth,
        height: targetHeight
      };
    } finally {
      if (targetMap !== pixelMap) {
        targetMap.release();
      }
    }
  }
}
