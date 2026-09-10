export interface AppConfig {
  env: 'dev' | 'staging' | 'prod';
  firebaseProject: string;
  version: string;
  enforceAppCheck: boolean;
  port: number;
}

export function getConfig(): AppConfig {
  const env = (process.env.NODE_ENV || 'dev') as 'dev' | 'staging' | 'prod';

  const firebaseProjectMap: Record<'dev' | 'staging' | 'prod', string> = {
    dev: 'picitydev',
    staging: 'picarestg',
    prod: 'picareprod',
  };

  return {
    env,
    firebaseProject: process.env.FIREBASE_PROJECT || firebaseProjectMap[env] || 'picitydev',
    version: process.env.APP_VERSION || '1.1.2',
    enforceAppCheck: process.env.ENFORCE_APP_CHECK === 'true' || env === 'prod',
    port: parseInt(process.env.PORT || '3000', 10),
  };
}
