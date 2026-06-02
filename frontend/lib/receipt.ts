import { RECEIPT_BASE_URL } from '@/lib/constants';

export function buildReceiptUrl(requestId: bigint): string {
  return `${RECEIPT_BASE_URL}${requestId}`;
}
