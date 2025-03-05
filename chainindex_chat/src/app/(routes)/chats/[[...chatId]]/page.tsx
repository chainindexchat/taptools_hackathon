import ChatItems from '@/client/components/chat/ChatItems';

import ChatInput from '@/client/components/chat-input/ChatInput';
import clsx from 'clsx';
// @ts-ignore
import { PageProps } from '../../../../../.next/types/app/(routes)/chats/[chatId]/page';
import { chatTermsAndConditions } from '@/client/components/support/pricing';
import { Typography } from '@chainindex/ui-custom';

export default async function Page({
  params,
}: PageProps & {
  params: {
    chatId: string[];
  };
}) {
  const [chatId] = (await params).chatId ?? [];
  return (
    <>
      <div
        className={clsx(
          'mx-auto',
          'w-full',
          'h-full',
          'max-w-[240rem]',
          'px-[3%]',
          'sm:px-[3%]',
          'md:px-[15%]',
          'lg:px-[20%]',
          'xl:px-[25%]',
          'overflow-y-hidden',
          'mb-12'
        )}
      >
        <div className="flex flex-col-reverse h-full w-full max-h-[90vh] overflow-y-hidden">
          {chatId && <ChatItems chatId={chatId} />}
        </div>
      </div>
      <div
        className={clsx(
          'mx-auto w-full max-w-[240rem] px-[3%] sm:px-[3%] md:px-[15%] lg:px-[20%] xl:px-[25%]',
          'relative',
          'bottom-0',
          'h-12',
          'flex',
          'flex-col',
          'items-start',
          'align-center'
        )}
      >
        <ChatInput chatId={chatId} />
        <div
          className={clsx(
            'w-full flex flex-col items-center justify-center pb-2'
          )}
        >
          {chatTermsAndConditions.map((item, index) => {
            return (
              <Typography
                key={`chat-terms-and-conditions-${index}-${Math.random()}-${Date.now()}`}
                variant="subtitle"
                className={clsx('justify-self-center')}
              >
                {item}
              </Typography>
            );
          })}
        </div>
      </div>
    </>
  );
}
