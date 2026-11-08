#ifndef CCURSORBRIDGE_H
#define CCURSORBRIDGE_H

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stdint.h>

// 非公開 API のシグネチャ。macOS 27.2 (arm64) の SkyLight / HIServices を逆アセンブルし、
// 引数レジスタの使われ方と一致することを確認した(docs/PHASE0.md)。
// 型の意味(どのポインタが size でどれが hotspot か)は実行時の戻り値で確かめている。
typedef int32_t CSConnectionID;
typedef int32_t CSError;

typedef CSConnectionID (*CSMainConnectionIDFn)(void);
typedef const char *_Nullable (*CSCursorNameForSystemCursorFn)(int32_t cursorID);
typedef CSError (*CSRegisterCursorWithImagesFn)(CSConnectionID cid, const char *_Nonnull name,
                                                bool setGlobally, bool instantly, CGSize size,
                                                CGPoint hotspot, uintptr_t frameCount,
                                                CGFloat frameDuration, CFArrayRef _Nonnull images,
                                                int32_t *_Nullable seed);
typedef CSError (*CSCopyRegisteredCursorImagesFn)(CSConnectionID cid, const char *_Nonnull name,
                                                  CGSize *_Nonnull size, CGPoint *_Nonnull hotspot,
                                                  uintptr_t *_Nonnull frameCount,
                                                  CGFloat *_Nonnull frameDuration,
                                                  CFArrayRef _Nullable *_Nonnull images);
typedef CSError (*CSRemoveRegisteredCursorFn)(CSConnectionID cid, const char *_Nonnull name,
                                              bool global);
typedef CSError (*CSCoreCursorUnregisterAllFn)(CSConnectionID cid);
typedef CSError (*CSCoreCursorCopyImagesFn)(CSConnectionID cid, int32_t cursorID,
                                            CFArrayRef _Nullable *_Nonnull images,
                                            CGSize *_Nonnull size, CGPoint *_Nonnull hotspot,
                                            uintptr_t *_Nonnull frameCount,
                                            CGFloat *_Nonnull frameDuration);
typedef CSError (*CSGetCursorScaleFn)(CSConnectionID cid, float *_Nonnull scale);

// HIServices の CoreCursorSet(cid, id)。名前 com.apple.cursor.<id> が未登録なら、HIServices 内蔵の
// 標準画像をグローバルに登録してから、呼び出したプロセスのカーソルに設定する。
typedef CSError (*CSCoreCursorSetFn)(CSConnectionID cid, int32_t cursorID);

// dlsym の結果。見つからないシンボルは NULL のまま。
typedef struct {
    CSMainConnectionIDFn _Nullable mainConnectionID;
    CSCursorNameForSystemCursorFn _Nullable cursorNameForSystemCursor;
    CSRegisterCursorWithImagesFn _Nullable registerCursorWithImages;
    CSCopyRegisteredCursorImagesFn _Nullable copyRegisteredCursorImages;
    CSRemoveRegisteredCursorFn _Nullable removeRegisteredCursor;
    CSCoreCursorUnregisterAllFn _Nullable coreCursorUnregisterAll;
    CSCoreCursorCopyImagesFn _Nullable coreCursorCopyImages;
    CSGetCursorScaleFn _Nullable getCursorScale;
    CSCoreCursorSetFn _Nullable coreCursorSet;
} CSSymbols;

CSSymbols CSResolveSymbols(void);

// AccessibilityFoundation の AXFCursorUnregisterAll。ポインター色を標準に戻したときにシステムが行う
// 再登録と同じ処理(同フレームワーク内蔵の標準画像を Arrow/ArrowS/IBeam/IBeamS に登録し、
// com.apple.accessibility.cursor.* と com.apple.cursor.13
// を削除する)。引数なし、設定は読み書きしない (macOS 27.2 の逆アセンブルで確認)。フレームワークを
// dlopen して解決する。見つからなければ NULL。
typedef void (*CSAXFCursorUnregisterAllFn)(void);
CSAXFCursorUnregisterAllFn _Nullable CSResolveAXFCursorUnregisterAll(void);

// シンボルを含むイメージのパス。見つからなければ NULL。
const char *_Nullable CSImagePathForSymbol(const char *_Nonnull symbol);

// 指定イメージの __TEXT,__cstring から prefix で始まる文字列を列挙する。
// OS が持つカーソル識別子名の候補を、固定表に頼らず拾うために使う。
typedef void (*CSStringVisitor)(const char *_Nonnull string, void *_Nullable context);
int CSScanCStrings(const char *_Nonnull imagePath, const char *_Nonnull prefix,
                   CSStringVisitor _Nonnull visitor, void *_Nullable context);

#endif
