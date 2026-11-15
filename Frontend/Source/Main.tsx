import { createRoot } from 'react-dom/client';
import { MantineProvider, createTheme } from '@mantine/core';
import '@mantine/core/styles.css';
import './Style.css';
import { App } from './App';
const theme = createTheme({
    primaryColor: 'teal',
    primaryShade: 4,
    fontFamily: 'Segoe UI, Inter, system-ui, sans-serif',
    defaultRadius: 'sm',
    colors: {
        dark: ['#d5e1ea', '#b4c6d2', '#8ba3b5', '#637f94', '#41586c', '#2b3c4d', '#1c2c3b', '#14212d', '#101a25', '#0b141e'],
        teal: ['#ecfcf5', '#d4f6e8', '#b5edd7', '#95e4c9', '#7edfc0', '#5dccaa', '#40ad8e', '#2d8c72', '#256f5b', '#1e5849'],
    },
});
createRoot(document.getElementById('root')!).render(<MantineProvider defaultColorScheme="dark" theme={theme}><App /></MantineProvider>);
