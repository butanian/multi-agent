export function makeId(environment: string, service: string): string {
  return `${environment.toLowerCase().trim()}::${service.toLowerCase().trim()}`;
}
