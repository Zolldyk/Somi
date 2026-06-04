'use client';

import { WagmiProvider } from 'wagmi';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { RainbowKitProvider, darkTheme } from '@rainbow-me/rainbowkit';
import { Toaster } from '@/components/ui/sonner';
import { AxeRunner } from '@/components/dev/AxeRunner';
import { config } from '@/lib/config';
import '@rainbow-me/rainbowkit/styles.css';

const queryClient = new QueryClient();

const somiTheme = darkTheme({
  accentColor: '#A855F7',
  accentColorForeground: '#FAFAFA',
  borderRadius: 'medium',
  overlayBlur: 'small',
});

somiTheme.colors = {
  ...somiTheme.colors,
  actionButtonBorder: '#27272A',
  actionButtonBorderMobile: '#27272A',
  actionButtonSecondaryBackground: '#1A1A1A',
  closeButton: '#A1A1AA',
  closeButtonBackground: '#1A1A1A',
  connectButtonBackground: '#0F0F0F',
  connectButtonBackgroundError: '#EF4444',
  connectButtonInnerBackground: '#1A1A1A',
  connectButtonText: '#FAFAFA',
  connectButtonTextError: '#FAFAFA',
  connectionIndicator: '#22C55E',
  downloadBottomCardBackground: '#0F0F0F',
  downloadTopCardBackground: '#1A1A1A',
  error: '#EF4444',
  generalBorder: '#27272A',
  generalBorderDim: '#1A1A1A',
  menuItemBackground: '#1A1A1A',
  modalBackdrop: 'rgba(10, 10, 10, 0.72)',
  modalBackground: '#0F0F0F',
  modalBorder: '#27272A',
  modalText: '#FAFAFA',
  modalTextDim: '#71717A',
  modalTextSecondary: '#A1A1AA',
  profileAction: '#1A1A1A',
  profileActionHover: '#27272A',
  profileForeground: '#0A0A0A',
  selectedOptionBorder: '#A855F7',
  standby: '#F59E0B',
};

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider theme={somiTheme}>
          <Toaster />
          {process.env.NODE_ENV !== 'production' && <AxeRunner />}
          {children}
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
