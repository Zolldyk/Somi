import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { somniaTestnet } from './chains';

export const config = getDefaultConfig({
  appName: 'Somi',
  projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID!,
  chains: [somniaTestnet],
  ssr: true,
});
