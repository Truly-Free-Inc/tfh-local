// tfh-local overlay ONLY (copied into the local image by docker/memberportal.Dockerfile; not in the memberportal repo).
// In production /dashboard is Builder.io content whose main block is the registered "Dashboard Page Content"
// component (src/builder-registry.ts -> DashboardContentWrapper). Builder is unreachable offline, so this route
// renders that same component with its Builder defaults. Data comes from the real portal -> tf-api calls; nothing
// is stubbed (order/subscription data that needs Sticky will be empty or error locally).
import { redirect } from 'next/navigation';
import DashboardContentWrapper from '@/components/builder/DashboardContent/DashboardContentWrapper';
import { checkIsUserLoginServer } from '@/helper/authLoginServer';
import { DEFAULT_REDIRECTS } from '@/lib/auth/routeConfig';

export const dynamic = 'force-dynamic';

export default async function TfhLocalDashboardPage() {
  if (!(await checkIsUserLoginServer())) redirect(DEFAULT_REDIRECTS.UNAUTHENTICATED);
  return (
    <div className="min-h-auto">
      <DashboardContentWrapper dashboardType="Dashboard with Subscriptions" dashboardVersion="new" />
    </div>
  );
}
