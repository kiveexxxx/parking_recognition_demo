let storage = new LocalStorage();

@Entry(storage)
@Component
struct ParkingCard {
  @LocalStorageProp('spotNo') private spotNo: string = '';
  @LocalStorageProp('areaNo') private areaNo: string = '';
  @LocalStorageProp('sourceText') private sourceText: string = '暂无记录';
  @LocalStorageProp('updatedAtText') private updatedAtText: string = '';
  @LocalStorageProp('emptyText') private emptyText: string = '暂无停车位置';

  build() {
    FormLink({
      action: 'router',
      abilityName: 'EntryAbility'
    }) {
      Column() {
        Text('停车位置')
          .fontSize(14)
          .fontColor('#52616B')
          .fontWeight(FontWeight.Medium)
        if (this.emptyText.length > 0) {
          Text(this.emptyText)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#8294A5')
            .margin({ top: 12 })
        } else {
          Text(this.locationText())
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor('#0F4C5C')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 10 })
          Text(`${this.sourceText}${this.updatedAtText.length > 0 ? ' · ' + this.updatedAtText : ''}`)
            .fontSize(11)
            .fontColor('#66788A')
            .maxLines(2)
            .margin({ top: 8 })
        }
      }
      .width('100%')
      .height('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start)
      .backgroundColor('#E8F6F3')
    }
  }

  private locationText(): string {
    const parts: string[] = [];
    if (this.areaNo.length > 0) {
      parts.push(`区域 ${this.areaNo}`);
    }
    if (this.spotNo.length > 0) {
      parts.push(`车位 ${this.spotNo}`);
    }
    return parts.length > 0 ? parts.join(' · ') : '停车位置已保存';
  }
}
