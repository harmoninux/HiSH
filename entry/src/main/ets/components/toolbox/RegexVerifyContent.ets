import { util } from "@kit.ArkTS";

interface Chunk {
  id: string
  content: string
  matched: boolean
}

function splitTextByRegex(text: string, regex: RegExp): Chunk[] {
  const segments: Chunk[] = [];
  const regexWithG = new RegExp(regex, regex.flags.includes('g') ? regex.flags : regex.flags + 'g');
  let lastEndIndex = 0;

  let match: RegExpExecArray | null = null;

  while ((match = regexWithG.exec(text)) !== null) {
    if (match.index > lastEndIndex) {
      segments.push({
        id: util.generateRandomUUID(),
        content: text.substring(lastEndIndex, match.index),
        matched: false
      });
    }
    segments.push({
      id: util.generateRandomUUID(),
      content: match[0],
      matched: true
    });

    lastEndIndex = regexWithG.lastIndex;
  }

  if (lastEndIndex < text.length) {
    segments.push({
      id: util.generateRandomUUID(),
      content: text.substring(lastEndIndex),
      matched: false
    });
  }

  return segments;
}

@Component
export struct RegexVerifyContent {
  @Watch('onRegexOrContentUpdate') @State regex: string = ''
  @Watch('onRegexOrContentUpdate') @State content: string = ''
  @State chunks: Chunk[] = []

  build() {
    Column() {
      TextInput({ text: this.regex, placeholder: '输入正则表达式，例如：\\d' })
        .margin({ bottom: 15 })
        .onChange((value) => {
          this.regex = value
        })
      TextArea({ text: this.content, placeholder: '输入验证文本，例如：1a2b' })
        .margin({ bottom: 15 })
        .height(120)
        .onChange((value) => {
          this.content = value
        })
      Column() {
        Row() {
          Text('匹配结果')
            .fontSize($r('sys.float.Body_L'))
            .fontColor($r('sys.color.font_secondary'))
            .margin({ bottom: 5 })
          Blank().layoutWeight(1)
          Text('匹配' + this.chunks.filter(it => it.matched).length.toString() + '个片段')
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_primary'))
            .margin({ bottom: 5 })
        }

        Column() {
          Text() {
            ForEach(this.chunks, (item: Chunk, i: number) => {
              Span(item.content)
                .fontColor(item.matched ? '#fff' : '#999')
            }, (item: Chunk, i: number) => item.id)
          }
          .width('100%')
        }
        .borderWidth(1)
        .borderRadius(10)
        .borderColor($r('app.color.setting_block_background_2'))
        .padding(5)
      }
      .backgroundColor($r('app.color.setting_block_background'))
      .borderRadius(10)
      .padding(10)
    }
  }

  onRegexOrContentUpdate() {
    try {
      if (this.regex.length > 0) {
        const reg = new RegExp(this.regex)
        this.chunks = splitTextByRegex(this.content, reg)
      } else {
        this.chunks = [{ id: util.generateRandomUUID(), content: this.content, matched: false }]
      }
    } catch (e) {
      this.chunks = [{ id: util.generateRandomUUID(), content: this.content, matched: false }]
    }
  }
}