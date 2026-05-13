import type { StorybookConfig } from '@storybook/nextjs';
import { storybookOnlookPlugin } from '@onlook/storybook-plugin';

const config: StorybookConfig = {
  stories: ['../components/**/*.stories.@(ts|tsx)', '../components/**/*.mdx'],
  addons: [],
  framework: {
    name: '@storybook/nextjs',
    options: {},
  },
  staticDirs: [],
  plugins: [storybookOnlookPlugin()],
};

export default config;
