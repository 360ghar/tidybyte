// Batch 14 insert — ja, ko, zh-Hans, ru
// Adds 8 plain strings + 2 counted strings to each language file.
// Snapshot of the pre-write state is dumped to /tmp/batch14-snapshot.json
// so the verify step can prove no pre-existing key changed.
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const dir = dirname(fileURLToPath(import.meta.url));

// Plain strings are inserted into .strings; counted into .plurals.
// Category sets: ja/ko/zh-Hans carry only "other"; ru carries one/few/many/other
// (confirmed from each file's existing 64 plural entries).
const T = {
  ja: {
    plain: {
      "Mixed": "混在",
      "Start here. ": "ここから開始。 ",
      "Untitled": "名称未設定",
      "media": "メディア",
      "Couldn't load this photo.": "この写真を読み込めませんでした。",
      "Couldn't load this video.": "このビデオを読み込めませんでした。",
      "Couldn't download this photo from iCloud.": "iCloudからこの写真をダウンロードできませんでした。",
      "Couldn't download this video from iCloud.": "iCloudからこのビデオをダウンロードできませんでした。",
    },
    plurals: {
      "%lld exact copies": { "other": "%lld個の完全一致コピー" },
      "%lld look-alike photos": { "other": "%lld枚の類似写真" },
    },
  },
  ko: {
    plain: {
      "Mixed": "혼합",
      "Start here. ": "여기서 시작. ",
      "Untitled": "제목 없음",
      "media": "미디어",
      "Couldn't load this photo.": "이 사진을 불러오지 못했습니다.",
      "Couldn't load this video.": "이 동영상을 불러오지 못했습니다.",
      "Couldn't download this photo from iCloud.": "iCloud에서 이 사진을 다운로드하지 못했습니다.",
      "Couldn't download this video from iCloud.": "iCloud에서 이 동영상을 다운로드하지 못했습니다.",
    },
    plurals: {
      "%lld exact copies": { "other": "%lld개의 완전 중복" },
      "%lld look-alike photos": { "other": "%lld장의 유사한 사진" },
    },
  },
  "zh-Hans": {
    plain: {
      "Mixed": "混合",
      "Start here. ": "从这里开始。 ",
      "Untitled": "未命名",
      "media": "媒体",
      "Couldn't load this photo.": "无法载入这张照片。",
      "Couldn't load this video.": "无法载入这个视频。",
      "Couldn't download this photo from iCloud.": "无法从 iCloud 下载这张照片。",
      "Couldn't download this video from iCloud.": "无法从 iCloud 下载这个视频。",
    },
    plurals: {
      "%lld exact copies": { "other": "%lld 个精确副本" },
      "%lld look-alike photos": { "other": "%lld 张相似照片" },
    },
  },
  ru: {
    plain: {
      "Mixed": "Смешанное",
      "Start here. ": "Начните здесь. ",
      "Untitled": "Без названия",
      "media": "медиафайл",
      "Couldn't load this photo.": "Не удалось загрузить это фото.",
      "Couldn't load this video.": "Не удалось загрузить это видео.",
      "Couldn't download this photo from iCloud.": "Не удалось скачать это фото из iCloud.",
      "Couldn't download this video from iCloud.": "Не удалось скачать это видео из iCloud.",
    },
    plurals: {
      "%lld exact copies": {
        "one": "%lld точная копия",
        "few": "%lld точные копии",
        "many": "%lld точных копий",
        "other": "%lld точной копии",
      },
      "%lld look-alike photos": {
        "one": "%lld похожее фото",
        "few": "%lld похожих фото",
        "many": "%lld похожих фото",
        "other": "%lld похожего фото",
      },
    },
  },
};

const snapshot = {};
for (const lang of Object.keys(T)) {
  const path = join(dir, `${lang}.json`);
  const j = JSON.parse(readFileSync(path, "utf8"));
  snapshot[lang] = JSON.parse(JSON.stringify(j)); // deep copy BEFORE mutating j

  for (const [k, v] of Object.entries(T[lang].plain)) j.strings[k] = v;
  for (const [k, v] of Object.entries(T[lang].plurals)) j.plurals[k] = v;

  // keep .strings key-sorted (plain code-unit sort, the file's existing order)
  j.strings = Object.fromEntries(
    Object.keys(j.strings).sort().map((k) => [k, j.strings[k]]),
  );

  writeFileSync(path, JSON.stringify(j, null, 2) + "\n");
  console.log(`${lang}.json written: strings=${Object.keys(j.strings).length} plurals=${Object.keys(j.plurals).length}`);
}

writeFileSync("/tmp/batch14-snapshot.json", JSON.stringify(snapshot));
console.log("snapshot -> /tmp/batch14-snapshot.json");
