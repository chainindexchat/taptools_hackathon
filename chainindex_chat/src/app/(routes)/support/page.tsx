import clsx from 'clsx';
import {
  poolSummary,
  supportIntro,
  termsAndConditions,
} from '@/client/components/support/pricing';
import { Card, IconSteak, Summary, Typography } from '@chainindex/ui-custom';
import { Warning } from '@/client/components/support/Warning';
import { Pricing } from '@/client/components/support/Pricing';
export default async function Page({ searchParams }) {
  const { rateLimited } = await searchParams; // access query parameters

  return (
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
        'mt-4'
      )}
    >
      <div
        className={clsx(
          'flex',
          'flex-col',
          'h-full',
          'w-full',
          'max-h-[90vh]',
          'pb-8'
        )}
      >
        <div
          className={clsx(
            'grid',
            'grid-cols-1',
            'md:grid-cols-2',
            'lg:grid-cols-2',
            'xl:grid-cols-2',
            'gap-4',
            'justify-items-center',
            'pb-4'
          )}
        >
          {rateLimited && <Warning />}
          <div className="col-span-full w-full flex space-x-2">
            <IconSteak />
            <Typography smallCaps element="h2">
              stake with CHAIN pool
            </Typography>
          </div>
          <div className="col-span-full w-full flex flex-col space-y-4">
            <Card className={'flex w-full'}>
              <div>
                <Typography indentParagraph element="p">
                  {supportIntro}
                </Typography>
              </div>
            </Card>
            <Card className={'flex w-full pr-8'}>
              <Summary data={poolSummary} />
            </Card>
          </div>
          <Pricing />
        </div>
        <div className={clsx('flex flex-col items-center justify-center ')}>
          {termsAndConditions.map((text, index) => {
            return (
              <Typography
                key={`terms-and-conditions-${index}-${Math.random()}-${Date.now()}`}
                variant="subtitle"
                className={clsx('justify-self-center')}
              >
                {text}
              </Typography>
            );
          })}
        </div>
      </div>
    </div>
  );
}
