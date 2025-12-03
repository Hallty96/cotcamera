import { z } from 'zod';

export const CreateSubmissionSchema = z.object({
  // use enum instead of literal-with-errorMap
  contentType: z.enum(['image/jpeg']),
  sizeBytes: z.number().int().positive(),
  imageSha256: z.string().regex(/^[a-f0-9]{64}$/),
  lat: z.number().min(-90).max(90).optional(),
  lng: z.number().min(-180).max(180).optional(),
  takenAt: z.string().datetime().optional()
});

export type CreateSubmissionInput = z.infer<typeof CreateSubmissionSchema>;
