export interface ParkingRecord {
  spotNo: string;
  areaNo?: string;
  confidence?: number;
  rawText?: string;
  source: 'manual' | 'photo' | 'voice' | 'camera_monitor';
  updatedAt: number;
}
