export type AuthProvider = 'anonymous' | 'apple' | 'wechat';

export interface User {
  id: string;
  createdAt: Date;
  updatedAt: Date;
  authProvider: AuthProvider;
  deviceId?: string;
  appleId?: string;
  wechatId?: string;
  ageRange?: 'under_18' | '18_24' | '25_34' | '35_44' | '45_plus';
  genderIdentity?: 'female' | 'male' | 'non_binary' | 'prefer_not_to_say' | 'other';
  colorPreference?: string;
}

export type DreamSource = 'iphone' | 'watch' | 'mini_program';

export type DreamStatus = 'recorded' | 'transcribed' | 'analyzed' | 'visualized';

export interface Dream {
  id: string;
  userId: string;
  createdAt: Date;
  updatedAt: Date;
  occurredAt: Date;
  source: DreamSource;
  audioUrl?: string;
  audioDurationSeconds?: number;
  rawTranscript?: string;
  segmentsCombinedTranscript?: string;
  refinedNarrative?: string;
  analysisText?: string;
  status: DreamStatus;
}

export interface DreamSegment {
  id: string;
  dreamId: string;
  index: number;
  createdAt: Date;
  audioUrl?: string;
  audioDurationSeconds?: number;
  transcript?: string;
}

export type TagCategory = 'person' | 'place' | 'object' | 'emotion' | 'theme' | 'scene_type' | 'other';

export interface Tag {
  id: string;
  name: string;
  category: TagCategory;
  createdAt: Date;
}

export interface DreamTag {
  id: string;
  dreamId: string;
  tagId: string;
  relevanceScore: number;
}

export type VisualType = 'four_panel_comic' | 'poster' | 'animation_10s';

export type VisualStatus = 'pending_payment' | 'queued' | 'generating' | 'succeeded' | 'failed';

export interface DreamVisual {
  id: string;
  dreamId: string;
  type: VisualType;
  styleKey: string;
  status: VisualStatus;
  createdAt: Date;
  updatedAt: Date;
  imageUrl?: string;
  failureReason?: string;
}

export interface SimilarityEdge {
  id: string;
  dreamIdA: string;
  dreamIdB: string;
  score: number;
  sharedTagIds: string[];
  createdAt: Date;
}

