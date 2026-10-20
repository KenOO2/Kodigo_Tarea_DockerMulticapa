import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Genera .next/standalone: un servidor mínimo con solo los node_modules
  // que realmente se usan. Es lo que permite una imagen final liviana.
  output: "standalone",
};

export default nextConfig;
