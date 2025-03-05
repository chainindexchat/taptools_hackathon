import type { Metadata } from 'next';

import '@workspace/ui/globals.css';
import '@chainindex/ui-custom/dist/style.css';

import BodyWrapper from '@/client/components/BodyWrapper';
import StoreProvider from '@/client/store/StoreProvider';
import { GoogleAnalytics } from '@next/third-parties/google';

export const metadata: Metadata = {
  title: 'ChainIndexChat',
  description: 'Query blockchain data with natural languge.',
};

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <head>
        <meta name="viewport" content="initial-scale=1, width=device-width" />
      </head>

      <StoreProvider>
        <BodyWrapper>{children}</BodyWrapper>
      </StoreProvider>
      {process.env.NODE_ENV === 'production' && (
        <GoogleAnalytics
          gaId={process.env.NEXT_PUBLIC_GOOGLE_ANALYTICS_ID as string}
        />
      )}
    </html>
  );
}
