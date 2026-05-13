import type { StorybookConfig } from '@storybook/nextjs-vite';
import { storybookOnlookPlugin } from '@onlook/storybook-plugin';

const config: StorybookConfig = {
  stories: ['../components/**/*.stories.@(ts|tsx)', '../components/**/*.mdx'],
  addons: [],
  framework: {
    name: '@storybook/nextjs-vite',
    options: {},
  },
  staticDirs: [],
  async viteFinal(config) {
    const { mergeConfig } = await import('vite');

    return mergeConfig(config, {
      plugins: [storybookOnlookPlugin()],
    });
  },
};

export default config;
