export type MarketStatus = 'Open' | 'Resolving' | 'LLMResolving' | 'Resolved' | 'Refunded' | 'Disputed';
export type Verdict = 'Unset' | 'YES' | 'NO' | 'INVALID';
export type AgentRequestType = 'None' | 'JsonApi' | 'Llm';

export const MARKET_STATUS: MarketStatus[] = ['Open', 'Resolving', 'LLMResolving', 'Resolved', 'Refunded', 'Disputed'];
export const VERDICT: Verdict[] = ['Unset', 'YES', 'NO', 'INVALID'];
export const AGENT_REQUEST_TYPE: AgentRequestType[] = ['None', 'JsonApi', 'Llm'];

export interface Market {
  id: bigint;
  creator: `0x${string}`;
  question: string;
  dataSource: string;
  jsonSelector: string;
  threshold: bigint;
  ambiguityBandBps: bigint;
  resolutionTime: bigint;
  yesPool: bigint;
  noPool: bigint;
  status: MarketStatus;
  verdict: Verdict;
  subscriptionId: bigint;
  pendingRequestId: bigint;
  pendingAgentType: AgentRequestType;
  resolvedAt: bigint;
}

export interface RawMarket {
  id: bigint;
  creator: `0x${string}`;
  question: string;
  dataSource: string;
  jsonSelector: string;
  threshold: bigint;
  ambiguityBandBps: bigint;
  resolutionTime: bigint;
  yesPool: bigint;
  noPool: bigint;
  status: number;
  verdict: number;
  subscriptionId: bigint;
  pendingRequestId: bigint;
  pendingAgentType: number;
  resolvedAt: bigint;
}
