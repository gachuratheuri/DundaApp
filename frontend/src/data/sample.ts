import type { DundaEvent } from '@/types/domain';

/**
 * Sample data used to drive the UI before the live API is wired in. Replace
 * `SAMPLE_EVENTS` with data fetched from the Dunda backend.
 */
export const SAMPLE_EVENTS: DundaEvent[] = [
  {
    id: 'evt_blankets',
    name: 'Blankets & Wine',
    venue: 'Lugogo Cricket Oval',
    date: 'SUN 14 JUN · 12:00',
    price: 3500,
    remaining: 1200,
    capacity: 5000,
  },
  {
    id: 'evt_sondeka',
    name: 'Sondeka Festival',
    venue: 'Two Rivers, Nairobi',
    date: 'SAT 27 JUN · 10:00',
    price: 2000,
    remaining: 320,
    capacity: 8000,
  },
  {
    id: 'evt_thrift',
    name: 'Thrift Social',
    venue: 'Alchemist Bar',
    date: 'SAT 06 JUN · 14:00',
    price: 500,
    remaining: 18,
    capacity: 600,
  },
  {
    id: 'evt_nairobinights',
    name: 'Nairobi Nights',
    venue: 'KICC Rooftop',
    date: 'FRI 12 JUN · 22:00',
    price: 1500,
    remaining: 0,
    capacity: 400,
  },
];
