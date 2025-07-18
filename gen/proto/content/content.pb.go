// FILE: proto/content/v1/content.proto

// Code generated by protoc-gen-go. DO NOT EDIT.
// versions:
// 	protoc-gen-go v1.36.6
// 	protoc        v5.29.3
// source: proto/content/content.proto

package content

import (
	protoreflect "google.golang.org/protobuf/reflect/protoreflect"
	protoimpl "google.golang.org/protobuf/runtime/protoimpl"
	reflect "reflect"
	sync "sync"
	unsafe "unsafe"
)

const (
	// Verify that this generated code is sufficiently up-to-date.
	_ = protoimpl.EnforceVersion(20 - protoimpl.MinVersion)
	// Verify that runtime/protoimpl is sufficiently up-to-date.
	_ = protoimpl.EnforceVersion(protoimpl.MaxVersion - 20)
)

// The request message containing a list of vocabulary IDs.
type GetVocabularyBatchRequest struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	VocabularyIds []string               `protobuf:"bytes,1,rep,name=vocabulary_ids,json=vocabularyIds,proto3" json:"vocabulary_ids,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *GetVocabularyBatchRequest) Reset() {
	*x = GetVocabularyBatchRequest{}
	mi := &file_proto_content_content_proto_msgTypes[0]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *GetVocabularyBatchRequest) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*GetVocabularyBatchRequest) ProtoMessage() {}

func (x *GetVocabularyBatchRequest) ProtoReflect() protoreflect.Message {
	mi := &file_proto_content_content_proto_msgTypes[0]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

// Deprecated: Use GetVocabularyBatchRequest.ProtoReflect.Descriptor instead.
func (*GetVocabularyBatchRequest) Descriptor() ([]byte, []int) {
	return file_proto_content_content_proto_rawDescGZIP(), []int{0}
}

func (x *GetVocabularyBatchRequest) GetVocabularyIds() []string {
	if x != nil {
		return x.VocabularyIds
	}
	return nil
}

// The response message containing a map of vocabulary IDs to Vocabulary objects
// for efficient lookup on the client side (the quiz-service).
type GetVocabularyBatchResponse struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	Items         map[string]*Vocabulary `protobuf:"bytes,1,rep,name=items,proto3" json:"items,omitempty" protobuf_key:"bytes,1,opt,name=key" protobuf_val:"bytes,2,opt,name=value"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *GetVocabularyBatchResponse) Reset() {
	*x = GetVocabularyBatchResponse{}
	mi := &file_proto_content_content_proto_msgTypes[1]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *GetVocabularyBatchResponse) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*GetVocabularyBatchResponse) ProtoMessage() {}

func (x *GetVocabularyBatchResponse) ProtoReflect() protoreflect.Message {
	mi := &file_proto_content_content_proto_msgTypes[1]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

// Deprecated: Use GetVocabularyBatchResponse.ProtoReflect.Descriptor instead.
func (*GetVocabularyBatchResponse) Descriptor() ([]byte, []int) {
	return file_proto_content_content_proto_rawDescGZIP(), []int{1}
}

func (x *GetVocabularyBatchResponse) GetItems() map[string]*Vocabulary {
	if x != nil {
		return x.Items
	}
	return nil
}

// Vocabulary message mirrors the structure of our Go model.
// 'optional' is used for fields that can be null in the database.
type Vocabulary struct {
	state         protoimpl.MessageState `protogen:"open.v1"`
	Id            string                 `protobuf:"bytes,1,opt,name=id,proto3" json:"id,omitempty"`
	Kana          string                 `protobuf:"bytes,2,opt,name=kana,proto3" json:"kana,omitempty"`
	Kanji         *string                `protobuf:"bytes,3,opt,name=kanji,proto3,oneof" json:"kanji,omitempty"`
	Furigana      *string                `protobuf:"bytes,4,opt,name=furigana,proto3,oneof" json:"furigana,omitempty"`
	Romaji        string                 `protobuf:"bytes,5,opt,name=romaji,proto3" json:"romaji,omitempty"`
	English       string                 `protobuf:"bytes,6,opt,name=english,proto3" json:"english,omitempty"`
	Burmese       string                 `protobuf:"bytes,7,opt,name=burmese,proto3" json:"burmese,omitempty"`
	Lesson        string                 `protobuf:"bytes,8,opt,name=lesson,proto3" json:"lesson,omitempty"`
	Type          string                 `protobuf:"bytes,9,opt,name=type,proto3" json:"type,omitempty"`
	WordClass     string                 `protobuf:"bytes,10,opt,name=word_class,json=wordClass,proto3" json:"word_class,omitempty"`
	unknownFields protoimpl.UnknownFields
	sizeCache     protoimpl.SizeCache
}

func (x *Vocabulary) Reset() {
	*x = Vocabulary{}
	mi := &file_proto_content_content_proto_msgTypes[2]
	ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
	ms.StoreMessageInfo(mi)
}

func (x *Vocabulary) String() string {
	return protoimpl.X.MessageStringOf(x)
}

func (*Vocabulary) ProtoMessage() {}

func (x *Vocabulary) ProtoReflect() protoreflect.Message {
	mi := &file_proto_content_content_proto_msgTypes[2]
	if x != nil {
		ms := protoimpl.X.MessageStateOf(protoimpl.Pointer(x))
		if ms.LoadMessageInfo() == nil {
			ms.StoreMessageInfo(mi)
		}
		return ms
	}
	return mi.MessageOf(x)
}

// Deprecated: Use Vocabulary.ProtoReflect.Descriptor instead.
func (*Vocabulary) Descriptor() ([]byte, []int) {
	return file_proto_content_content_proto_rawDescGZIP(), []int{2}
}

func (x *Vocabulary) GetId() string {
	if x != nil {
		return x.Id
	}
	return ""
}

func (x *Vocabulary) GetKana() string {
	if x != nil {
		return x.Kana
	}
	return ""
}

func (x *Vocabulary) GetKanji() string {
	if x != nil && x.Kanji != nil {
		return *x.Kanji
	}
	return ""
}

func (x *Vocabulary) GetFurigana() string {
	if x != nil && x.Furigana != nil {
		return *x.Furigana
	}
	return ""
}

func (x *Vocabulary) GetRomaji() string {
	if x != nil {
		return x.Romaji
	}
	return ""
}

func (x *Vocabulary) GetEnglish() string {
	if x != nil {
		return x.English
	}
	return ""
}

func (x *Vocabulary) GetBurmese() string {
	if x != nil {
		return x.Burmese
	}
	return ""
}

func (x *Vocabulary) GetLesson() string {
	if x != nil {
		return x.Lesson
	}
	return ""
}

func (x *Vocabulary) GetType() string {
	if x != nil {
		return x.Type
	}
	return ""
}

func (x *Vocabulary) GetWordClass() string {
	if x != nil {
		return x.WordClass
	}
	return ""
}

var File_proto_content_content_proto protoreflect.FileDescriptor

const file_proto_content_content_proto_rawDesc = "" +
	"\n" +
	"\x1bproto/content/content.proto\x12\acontent\"B\n" +
	"\x19GetVocabularyBatchRequest\x12%\n" +
	"\x0evocabulary_ids\x18\x01 \x03(\tR\rvocabularyIds\"\xb1\x01\n" +
	"\x1aGetVocabularyBatchResponse\x12D\n" +
	"\x05items\x18\x01 \x03(\v2..content.GetVocabularyBatchResponse.ItemsEntryR\x05items\x1aM\n" +
	"\n" +
	"ItemsEntry\x12\x10\n" +
	"\x03key\x18\x01 \x01(\tR\x03key\x12)\n" +
	"\x05value\x18\x02 \x01(\v2\x13.content.VocabularyR\x05value:\x028\x01\"\x9a\x02\n" +
	"\n" +
	"Vocabulary\x12\x0e\n" +
	"\x02id\x18\x01 \x01(\tR\x02id\x12\x12\n" +
	"\x04kana\x18\x02 \x01(\tR\x04kana\x12\x19\n" +
	"\x05kanji\x18\x03 \x01(\tH\x00R\x05kanji\x88\x01\x01\x12\x1f\n" +
	"\bfurigana\x18\x04 \x01(\tH\x01R\bfurigana\x88\x01\x01\x12\x16\n" +
	"\x06romaji\x18\x05 \x01(\tR\x06romaji\x12\x18\n" +
	"\aenglish\x18\x06 \x01(\tR\aenglish\x12\x18\n" +
	"\aburmese\x18\a \x01(\tR\aburmese\x12\x16\n" +
	"\x06lesson\x18\b \x01(\tR\x06lesson\x12\x12\n" +
	"\x04type\x18\t \x01(\tR\x04type\x12\x1d\n" +
	"\n" +
	"word_class\x18\n" +
	" \x01(\tR\twordClassB\b\n" +
	"\x06_kanjiB\v\n" +
	"\t_furigana2o\n" +
	"\x0eContentService\x12]\n" +
	"\x12GetVocabularyBatch\x12\".content.GetVocabularyBatchRequest\x1a#.content.GetVocabularyBatchResponseB\x1cZ\x1awise-owl/gen/proto/contentb\x06proto3"

var (
	file_proto_content_content_proto_rawDescOnce sync.Once
	file_proto_content_content_proto_rawDescData []byte
)

func file_proto_content_content_proto_rawDescGZIP() []byte {
	file_proto_content_content_proto_rawDescOnce.Do(func() {
		file_proto_content_content_proto_rawDescData = protoimpl.X.CompressGZIP(unsafe.Slice(unsafe.StringData(file_proto_content_content_proto_rawDesc), len(file_proto_content_content_proto_rawDesc)))
	})
	return file_proto_content_content_proto_rawDescData
}

var file_proto_content_content_proto_msgTypes = make([]protoimpl.MessageInfo, 4)
var file_proto_content_content_proto_goTypes = []any{
	(*GetVocabularyBatchRequest)(nil),  // 0: content.GetVocabularyBatchRequest
	(*GetVocabularyBatchResponse)(nil), // 1: content.GetVocabularyBatchResponse
	(*Vocabulary)(nil),                 // 2: content.Vocabulary
	nil,                                // 3: content.GetVocabularyBatchResponse.ItemsEntry
}
var file_proto_content_content_proto_depIdxs = []int32{
	3, // 0: content.GetVocabularyBatchResponse.items:type_name -> content.GetVocabularyBatchResponse.ItemsEntry
	2, // 1: content.GetVocabularyBatchResponse.ItemsEntry.value:type_name -> content.Vocabulary
	0, // 2: content.ContentService.GetVocabularyBatch:input_type -> content.GetVocabularyBatchRequest
	1, // 3: content.ContentService.GetVocabularyBatch:output_type -> content.GetVocabularyBatchResponse
	3, // [3:4] is the sub-list for method output_type
	2, // [2:3] is the sub-list for method input_type
	2, // [2:2] is the sub-list for extension type_name
	2, // [2:2] is the sub-list for extension extendee
	0, // [0:2] is the sub-list for field type_name
}

func init() { file_proto_content_content_proto_init() }
func file_proto_content_content_proto_init() {
	if File_proto_content_content_proto != nil {
		return
	}
	file_proto_content_content_proto_msgTypes[2].OneofWrappers = []any{}
	type x struct{}
	out := protoimpl.TypeBuilder{
		File: protoimpl.DescBuilder{
			GoPackagePath: reflect.TypeOf(x{}).PkgPath(),
			RawDescriptor: unsafe.Slice(unsafe.StringData(file_proto_content_content_proto_rawDesc), len(file_proto_content_content_proto_rawDesc)),
			NumEnums:      0,
			NumMessages:   4,
			NumExtensions: 0,
			NumServices:   1,
		},
		GoTypes:           file_proto_content_content_proto_goTypes,
		DependencyIndexes: file_proto_content_content_proto_depIdxs,
		MessageInfos:      file_proto_content_content_proto_msgTypes,
	}.Build()
	File_proto_content_content_proto = out.File
	file_proto_content_content_proto_goTypes = nil
	file_proto_content_content_proto_depIdxs = nil
}
