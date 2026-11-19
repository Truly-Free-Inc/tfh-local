// tfh-local overlay ONLY (copied into the local image by docker/memberportal.Dockerfile; not in the memberportal repo).
// In production /login is Builder.io content ("member-portal-pages"). Builder is unreachable in offline mode, so
// this route renders the portal's REAL LoginForm component; the submit path (portal route -> tf-api
// /portal/api/v1/auth/login -> session cookies) is unchanged. Nothing about orders or payments is faked.
import { redirect } from 'next/navigation';
import LoginForm from '@/components/builder/LoginForm/LoginForm';
import { checkIsUserLoginServer } from '@/helper/authLoginServer';
import { DEFAULT_REDIRECTS } from '@/lib/auth/routeConfig';

export const dynamic = 'force-dynamic';

export default async function TfhLocalLoginPage() {
  if (await checkIsUserLoginServer()) redirect(DEFAULT_REDIRECTS.AUTHENTICATED);
  return (
    <div className="min-h-auto mx-auto max-w-md px-4 py-16">
      <h1 className="mb-2 text-2xl font-semibold">Member login</h1>
      <p className="mb-6 text-sm text-gray-500">tfh-local (offline): Builder page content replaced by the real login form.</p>
      <LoginForm />
    </div>
  );
}
