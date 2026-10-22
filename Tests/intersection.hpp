inline float dot(V3 a,V3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
inline bool pierces(V3 p,V3 q,V3 a,V3 b,V3 c){
 V3 n=cross(b-a,c-a);float den=dot(n,q-p);if(std::abs(den)<1e-5)return false;float t=dot(n,a-p)/den;if(t<.0001f||t>.9999f)return false;V3 at=p+(q-p)*t;V3 u=b-a,v=c-a,w=at-a;float uu=dot(u,u),uv=dot(u,v),vv=dot(v,v),wu=dot(w,u),wv=dot(w,v),det=uu*vv-uv*uv;if(std::abs(det)<1e-8)return false;float s=(vv*wu-uv*wv)/det,r=(uu*wv-uv*wu)/det;return s>.0001f&&r>.0001f&&s+r<.9999f;
}
int intersections(const Cloth&c){
 struct Box{V3 lo,hi;};std::vector<Box> boxes;for(auto f:c.faces){Box b{c.pos[f[0]],c.pos[f[0]]};for(int v:f){auto p=c.pos[v];b.lo={std::min(b.lo.x,p.x),std::min(b.lo.y,p.y),std::min(b.lo.z,p.z)};b.hi={std::max(b.hi.x,p.x),std::max(b.hi.y,p.y),std::max(b.hi.z,p.z)};}boxes.push_back(b);}
 int count=0;for(int i=0;i<int(c.faces.size());i++)for(int j=i+1;j<int(c.faces.size());j++){
  auto b=boxes[i],d=boxes[j];if(b.lo.x>d.hi.x||d.lo.x>b.hi.x||b.lo.y>d.hi.y||d.lo.y>b.hi.y||b.lo.z>d.hi.z||d.lo.z>b.hi.z)continue;
  auto f=c.faces[i],g=c.faces[j];bool shared=false;for(int v:f)for(int w:g)shared|=v==w;if(shared)continue;
  bool cross=false;for(int v=0;v<3;v++){cross|=pierces(c.pos[f[v]],c.pos[f[(v+1)%3]],c.pos[g[0]],c.pos[g[1]],c.pos[g[2]]);cross|=pierces(c.pos[g[v]],c.pos[g[(v+1)%3]],c.pos[f[0]],c.pos[f[1]],c.pos[f[2]]);}count+=cross;
 }return count;
}
