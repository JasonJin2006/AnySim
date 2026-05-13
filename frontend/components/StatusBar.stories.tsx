import type { Meta, StoryObj } from '@storybook/nextjs';

import { StatusBar } from './StatusBar';

const meta = {
  title: 'Components/StatusBar',
  component: StatusBar,
  parameters: {
    layout: 'padded',
  },
  args: {
    connectionStatus: 'connected',
    running: true,
    paused: false,
    currentTime: 36,
    stepCount: 128,
    speed: 2,
    entityCount: 14,
    modelName: 'Shipping Demo',
  },
} satisfies Meta<typeof StatusBar>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Default: Story = {};
